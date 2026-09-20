import '../../../../core/result.dart';
import '../../../groups/domain/entities/schedule.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';
import 'ensure_upcoming_sessions.dart';

/// Saves a new weekly schedule (or removes it with `null`) and rebuilds the
/// future sessions that the old schedule created.
class UpdateSchedule {
  UpdateSchedule(this._groups, this._sessions, this._guard, this._ensure, this._now);

  final GroupRepository _groups;
  final SessionRepository _sessions;
  final OrganizerGuard _guard;
  final EnsureUpcomingSessions _ensure;
  final DateTime Function() _now;

  Future<Result<int>> call({
    required String groupId,
    required String actingUserId,
    required Schedule? schedule,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();

    final saved = await _groups.updateGroup(guard.value.copyWith(schedule: () => schedule));
    if (saved.isErr) return saved.castErr();

    // Remove future occurrences created by the old rule: still scheduled,
    // never edited, and with nobody checked in.
    final future = await _sessions.getSessionsStartingAfter(groupId, _now());
    if (future.isErr) return future.castErr();
    for (final session in future.value) {
      if (session.status != SessionStatus.scheduled || session.modified) continue;
      final checkIns = await _sessions.getCheckIns(groupId, session.id);
      if (checkIns.isErr) return checkIns.castErr();
      if (checkIns.value.isNotEmpty) continue;
      final deleted = await _sessions.deleteSession(groupId, session.id);
      if (deleted.isErr) return deleted.castErr();
    }
    return _ensure(groupId: groupId, userId: actingUserId);
  }
}
