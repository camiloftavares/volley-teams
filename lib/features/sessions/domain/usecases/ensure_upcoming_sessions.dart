import '../../../../core/result.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';
import '../services/schedule_expander.dart';

/// Materializes the group's weekly schedule into concrete sessions.
/// Idempotent: existing sessions (edited, cancelled or not) are never touched.
class EnsureUpcomingSessions {
  EnsureUpcomingSessions(this._groups, this._sessions, this._expander, this._now);

  final GroupRepository _groups;
  final SessionRepository _sessions;
  final ScheduleExpander _expander;
  final DateTime Function() _now;

  /// Returns how many sessions were created. Does nothing (returns 0) for
  /// anyone but the organizer, or when the group has no schedule.
  Future<Result<int>> call({required String groupId, required String userId}) async {
    final groupResult = await _groups.getGroup(groupId);
    if (groupResult.isErr) return groupResult.castErr();
    final group = groupResult.value;
    final schedule = group.schedule;
    if (group.organizerId != userId || schedule == null) return const Ok(0);

    var created = 0;
    for (final occurrence in _expander.expand(schedule: schedule, now: _now())) {
      final result = await _sessions.createIfAbsent(
        groupId,
        GameSession.scheduled(
          id: occurrence.id,
          startsAt: occurrence.startsAt,
          teamSize: group.defaultTeamSize,
          court: group.court,
          radiusMeters: group.radiusMeters,
        ),
      );
      if (result.isErr) return result.castErr();
      if (result.value) created++;
    }
    return Ok(created);
  }
}
