import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../failure.dart';
import '../result.dart';

/// Runs [body], turning Firestore and unexpected exceptions into failures so
/// they never cross the data-layer boundary.
Future<Result<T>> guardFirestoreResult<T>(Future<Result<T>> Function() body) async {
  try {
    return await body();
  } on FirebaseException catch (e) {
    return Err(_failureFor(e));
  } catch (e) {
    return Err(Unexpected('$e'));
  }
}

/// Like [guardFirestoreResult] for a body that simply returns a value.
Future<Result<T>> guardFirestore<T>(Future<T> Function() body) =>
    guardFirestoreResult(() async => Ok(await body()));

/// Re-emits every error of [source] as a [Failure], so a snapshot listener
/// (permission revoked, offline, a mapper cast error) never leaks a raw
/// exception through `AsyncValue.error`.
Stream<T> guardFirestoreStream<T>(Stream<T> source) => source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleError: (error, stack, sink) => sink.addError(_toFailure(error), stack),
      ),
    );

Failure _toFailure(Object error) =>
    error is Failure ? error : error is FirebaseException ? _failureFor(error) : Unexpected('$error');

Failure _failureFor(FirebaseException e) => switch (e.code) {
      'permission-denied' => const Unauthorized(),
      'unavailable' || 'deadline-exceeded' => const Offline(),
      'not-found' => NotFound(e.message ?? 'document'),
      _ => Unexpected(e.message ?? e.code),
    };
