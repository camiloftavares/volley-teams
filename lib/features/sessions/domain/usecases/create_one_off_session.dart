import '../../../../core/failure.dart';
import '../../../../core/random_codes.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class CreateOneOffSession {
  CreateOneOffSession(this._guard, this._sessions, this._codes);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;
  final RandomCodes _codes;

  Future<Result<GameSession>> call({
    required String groupId,
    required String actingUserId,
    required DateTime startsAt,
    int? teamSize,
  }) async {
    if (teamSize != null && teamSize < 2) {
      return const Err(InvalidInput('A team needs at least 2 players'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final group = guard.value;
    // `modified: true` keeps the recurring schedule from ever replacing it.
    final session = GameSession.scheduled(
      id: 'one-off-${_codes.id(12)}',
      startsAt: startsAt.toUtc(),
      teamSize: teamSize ?? group.defaultTeamSize,
      court: group.court,
      radiusMeters: group.radiusMeters,
      modified: true,
    );
    final written = await _sessions.createIfAbsent(groupId, session);
    return written.isErr ? written.castErr() : Ok(session);
  }
}
