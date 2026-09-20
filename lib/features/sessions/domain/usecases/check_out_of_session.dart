import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../repositories/session_repository.dart';

class CheckOutOfSession {
  CheckOutOfSession(this._sessions);

  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String userId,
  }) =>
      _sessions.checkOut(groupId, sessionId, userId);
}

/// Organizer removes someone else's check-in (a misclick or a suspicious one).
class RemoveCheckIn {
  RemoveCheckIn(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    required String targetUserId,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _sessions.checkOut(groupId, sessionId, targetUserId);
  }
}
