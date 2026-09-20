import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class CancelSession {
  CancelSession(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found.castErr();
    final session = found.value;
    if (session.status == SessionStatus.teamsPublished) {
      return const Err(SessionAlreadyPublished());
    }
    if (session.status == SessionStatus.cancelled) return const Ok<void>(null);
    return _sessions.updateSession(
      groupId,
      session.copyWith(status: SessionStatus.cancelled, modified: true),
    );
  }
}
