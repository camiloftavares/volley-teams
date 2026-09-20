import 'package:equatable/equatable.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../groups/domain/entities/schedule.dart';
import '../entities/game_session.dart';

class SessionOccurrence extends Equatable {
  const SessionOccurrence({required this.id, required this.startsAt});

  /// Deterministic: the local date-time in the schedule's timezone,
  /// e.g. `2026-09-22T19:00`.
  final String id;

  /// UTC instant.
  final DateTime startsAt;

  @override
  List<Object?> get props => [id, startsAt];
}

/// Expands a weekly [Schedule] into concrete occurrences.
///
/// Requires `tz.initializeTimeZones()` to have run.
class ScheduleExpander {
  const ScheduleExpander();

  static const defaultHorizonDays = 28;

  /// Occurrences within [horizonDays] local days starting today, plus yesterday
  /// (a late game's check-in window can still be open after midnight). A game
  /// whose check-in window has already closed is skipped.
  List<SessionOccurrence> expand({
    required Schedule schedule,
    required DateTime now,
    int horizonDays = defaultHorizonDays,
  }) {
    final location = tz.getLocation(schedule.timezone);
    final localNow = tz.TZDateTime.from(now, location);
    // Plain UTC dates are used only for calendar arithmetic (no DST surprises).
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final end = schedule.endDate;
    final lastDay = end == null ? null : DateTime.utc(end.year, end.month, end.day);

    final occurrences = <SessionOccurrence>[];
    for (var offset = -1; offset < horizonDays; offset++) {
      final day = today.add(Duration(days: offset));
      if (lastDay != null && day.isAfter(lastDay)) break;
      if (!schedule.weekdays.contains(day.weekday)) continue;
      final start = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        schedule.startTime.hour,
        schedule.startTime.minute,
      );
      if (!start.add(GameSession.checkInClosesAfter).isAfter(now)) continue;
      occurrences.add(SessionOccurrence(
        id: _idFor(start),
        startsAt: DateTime.fromMillisecondsSinceEpoch(
          start.millisecondsSinceEpoch,
          isUtc: true,
        ),
      ));
    }
    return occurrences;
  }

  String _idFor(tz.TZDateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}';
  }
}
