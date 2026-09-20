import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

/// Changes one occurrence (team size and/or start time) without touching the
/// schedule. The session is marked `modified` so the schedule leaves it alone.
class EditSession {
  EditSession(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<GameSession>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    int? teamSize,
    DateTime? startsAt,
  }) async {
    if (teamSize != null && teamSize < 2) {
      return const Err(InvalidInput('A team needs at least 2 players'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found;
    final session = found.value;
    if (session.status == SessionStatus.teamsPublished) {
      return const Err(SessionAlreadyPublished());
    }
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());

    final updated = session.copyWith(
      teamSize: teamSize,
      startsAt: startsAt?.toUtc(),
      modified: true,
    );
    final written = await _sessions.updateSession(groupId, updated);
    return written.isErr ? written.castErr() : Ok(updated);
  }
}
