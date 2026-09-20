import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/data/firestore_guard.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/failure_message.dart';

FirebaseException firebaseError(String code, [String? message]) =>
    FirebaseException(plugin: 'cloud_firestore', code: code, message: message);

void main() {
  group('guardFirestore', () {
    test('permission-denied becomes Unauthorized without Firebase wording', () async {
      final result = await guardFirestore<void>(() async {
        throw firebaseError('permission-denied', 'Missing or insufficient permissions.');
      });

      expect(result.isErr, isTrue);
      final failure = result.failure;
      expect(failure, isA<Unauthorized>());
      expect(failure.message, isNull);
      expect(failureMessage(failure), 'You are not allowed to do that.');
    });

    test('returns the value when the body succeeds', () async {
      final result = await guardFirestore(() async => 7);
      expect(result.isOk, isTrue);
      expect(result.value, 7);
    });
  });

  group('guardFirestoreStream', () {
    Future<List<Object>> collectErrors(Stream<int> source) async {
      final errors = <Object>[];
      await guardFirestoreStream(source).handleError(errors.add).drain<void>();
      return errors;
    }

    test('passes values through unchanged', () async {
      final values = await guardFirestoreStream(Stream.fromIterable([1, 2, 3])).toList();
      expect(values, [1, 2, 3]);
    });

    test('permission-denied is re-emitted as an Unauthorized failure', () async {
      final errors = await collectErrors(
        Stream<int>.error(firebaseError('permission-denied', 'Missing or insufficient permissions.')),
      );
      expect(errors, hasLength(1));
      expect(errors.single, isA<Unauthorized>());
      expect((errors.single as Failure).message, isNull);
    });

    test('unavailable is re-emitted as Offline', () async {
      final errors = await collectErrors(Stream<int>.error(firebaseError('unavailable')));
      expect(errors.single, isA<Offline>());
    });

    test('a non-Firebase error becomes Unexpected', () async {
      final errors = await collectErrors(Stream<int>.error(StateError('boom')));
      expect(errors.single, isA<Unexpected>());
    });

    test('values before an error are still delivered', () async {
      final controller = StreamController<int>();
      final values = <int>[];
      final errors = <Object>[];
      final done = Completer<void>();
      guardFirestoreStream(controller.stream)
          .listen(values.add, onError: errors.add, onDone: done.complete);
      controller
        ..add(1)
        ..addError(firebaseError('unavailable'))
        ..add(2);
      await controller.close();
      await done.future;
      expect(values, [1, 2]);
      expect(errors.single, isA<Offline>());
    });
  });
}
