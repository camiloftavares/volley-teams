import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../../../sessions/domain/entities/team.dart';
import '../../../sessions/domain/repositories/session_repository.dart';

class PublishTeams {
  PublishTeams(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    required List<Team> teams,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _sessions.publishTeams(groupId, sessionId, teams);
  }
}
