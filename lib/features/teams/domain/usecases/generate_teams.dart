import 'dart:math';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../../../sessions/domain/entities/game_session.dart';
import '../../../sessions/domain/entities/team.dart';
import '../../../sessions/domain/repositories/session_repository.dart';
import '../services/team_balancer.dart';

/// Builds a team preview from the current check-ins. Nothing is persisted;
/// call it again for a reshuffle.
class GenerateTeams {
  GenerateTeams(this._guard, this._groups, this._sessions, this._balancer, this._random);

  final OrganizerGuard _guard;
  final GroupRepository _groups;
  final SessionRepository _sessions;
  final TeamBalancer _balancer;
  final Random _random;

  Future<Result<List<Team>>> call({
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
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());

    final checkIns = await _sessions.getCheckIns(groupId, sessionId);
    if (checkIns.isErr) return checkIns.castErr();
    final members = await _groups.getMembers(groupId);
    if (members.isErr) return members.castErr();

    final ratings = {for (final m in members.value) m.userId: m.effectiveRating};
    // A stable order keeps seeded runs reproducible.
    final ordered = [...checkIns.value]..sort((a, b) {
        final byTime = a.checkedInAt.compareTo(b.checkedInAt);
        return byTime != 0 ? byTime : a.userId.compareTo(b.userId);
      });
    final players = [
      for (final c in ordered)
        if (ratings[c.userId] != null) RatedPlayer(id: c.userId, rating: ratings[c.userId]!),
    ];
    return _balancer.balance(players: players, teamSize: session.teamSize, random: _random);
  }
}
