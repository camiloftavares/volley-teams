import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/sessions/domain/services/schedule_expander.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const expander = ScheduleExpander();

  const sundays = Schedule(
    weekdays: {DateTime.sunday},
    startTime: LocalTime(19, 0),
    timezone: 'America/New_York',
  );

  test('expands four weekly Sundays and keeps 19:00 local across the DST change', () {
    // 2026-03-01 is a Sunday; US daylight time starts on 2026-03-08.
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 1, 12));
    expect(result.map((o) => o.id), [
      '2026-03-01T19:00',
      '2026-03-08T19:00',
      '2026-03-15T19:00',
      '2026-03-22T19:00',
    ]);
    expect(result.map((o) => o.startsAt), [
      DateTime.utc(2026, 3, 2, 0), // 19:00 EST (UTC-5)
      DateTime.utc(2026, 3, 8, 23), // 19:00 EDT (UTC-4)
      DateTime.utc(2026, 3, 15, 23),
      DateTime.utc(2026, 3, 22, 23),
    ]);
    expect(result.every((o) => o.startsAt.isUtc), isTrue);
  });

  test('supports several weekdays', () {
    const tueThu = Schedule(
      weekdays: {DateTime.tuesday, DateTime.thursday},
      startTime: LocalTime(19, 30),
      timezone: 'America/New_York',
    );
    final result = expander.expand(schedule: tueThu, now: DateTime.utc(2026, 3, 1, 12));
    expect(result, hasLength(8));
    expect(result.first.id, '2026-03-03T19:30');
    expect(result.last.id, '2026-03-26T19:30');
  });

  test('stops at the end date (inclusive)', () {
    final ending = Schedule(
      weekdays: sundays.weekdays,
      startTime: sundays.startTime,
      timezone: sundays.timezone,
      endDate: DateTime(2026, 3, 8),
    );
    final result = expander.expand(schedule: ending, now: DateTime.utc(2026, 3, 1, 12));
    expect(result.map((o) => o.id), ['2026-03-01T19:00', '2026-03-08T19:00']);
  });

  test('skips a game whose check-in window has already closed', () {
    // 2026-03-02 12:00 UTC is after the Mar 1 game's window (closes 03:00 UTC).
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 2, 12));
    expect(result.first.id, '2026-03-08T19:00');
    expect(result, hasLength(4)); // Mar 8, 15, 22, 29
  });

  test('keeps a game that started but whose check-in is still open', () {
    // 2026-03-02 01:00 UTC = 20:00 EST on Mar 1: the 19:00 game is under way.
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 2, 1));
    expect(result.first.id, '2026-03-01T19:00');
  });

  group('a game from yesterday whose window is still open', () {
    const lateSaturday = Schedule(
      weekdays: {DateTime.saturday},
      startTime: LocalTime(22, 0),
      timezone: 'America/New_York',
    );

    test('is materialised (Sat 22:00 game, opened at 00:30 Sunday local)', () {
      // 2026-03-01 05:30 UTC = 00:30 EST Sunday; the window closes at 06:00 UTC.
      final result = expander.expand(schedule: lateSaturday, now: DateTime.utc(2026, 3, 1, 5, 30));
      expect(result.first.id, '2026-02-28T22:00');
      expect(result.first.startsAt, DateTime.utc(2026, 3, 1, 3));
    });

    test('is not returned once its window has closed', () {
      final result = expander.expand(schedule: lateSaturday, now: DateTime.utc(2026, 3, 1, 7));
      expect(result.first.id, '2026-03-07T22:00');
      expect(result.map((o) => o.id), isNot(contains('2026-02-28T22:00')));
    });
  });

  test('ids are stable when expanding twice', () {
    final now = DateTime.utc(2026, 3, 1, 12);
    expect(expander.expand(schedule: sundays, now: now),
        expander.expand(schedule: sundays, now: now));
  });
}
