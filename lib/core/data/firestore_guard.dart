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

Failure _failureFor(FirebaseException e) => switch (e.code) {
      'permission-denied' => Unauthorized(e.message),
      'unavailable' || 'deadline-exceeded' => const Offline(),
      'not-found' => NotFound(e.message ?? 'document'),
      _ => Unexpected(e.message ?? e.code),
    };
