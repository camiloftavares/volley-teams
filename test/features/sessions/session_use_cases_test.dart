import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/random_codes.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/services/schedule_expander.dart';
import 'package:volley_teams/features/sessions/domain/usecases/cancel_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/create_one_off_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/edit_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/ensure_upcoming_sessions.dart';
import 'package:volley_teams/features/sessions/domain/usecases/update_schedule.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_session_repository.dart';

const sundays = Schedule(
  weekdays: {DateTime.sunday},
  startTime: LocalTime(19, 0),
  timezone: 'America/New_York',
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // 2026-03-01 12:00 UTC is a Sunday morning in New York.
  final now = DateTime.utc(2026, 3, 1, 12);
  late FakeGroupRepository groups;
  late FakeSessionRepository sessions;
  late OrganizerGuard guard;
  late EnsureUpcomingSessions ensure;

  Group makeGroup({Schedule? schedule}) => Group(
        id: 'g1', name: 'G', organizerId: 'ana', inviteCode: 'ABCDEFGH',
        court: const Coordinates(1, 1), schedule: schedule,
      );

  setUp(() {
    groups = FakeGroupRepository()..groups['g1'] = makeGroup(schedule: sundays);
    sessions = FakeSessionRepository();
    guard = OrganizerGuard(groups);
    ensure = EnsureUpcomingSessions(groups, sessions, const ScheduleExpander(), () => now);
  });

  group('EnsureUpcomingSessions', () {
    test('creates the next four Sundays with the group defaults', () async {
      final created = await ensure(groupId: 'g1', userId: 'ana');
      expect(created.value, 4);
      final all = sessions.sessions['g1']!;
      expect(all.keys, ['2026-03-01T19:00', '2026-03-08T19:00', '2026-03-15T19:00', '2026-03-22T19:00']);
      expect(all['2026-03-08T19:00']!.teamSize, 6);
      expect(all['2026-03-08T19:00']!.court, const Coordinates(1, 1));
      expect(all['2026-03-08T19:00']!.startsAt, DateTime.utc(2026, 3, 8, 23));
    });

    test('is idempotent and never overwrites an edited or cancelled occurrence', () async {
      await ensure(groupId: 'g1', userId: 'ana');
      final cancelled = sessions.sessions['g1']!['2026-03-08T19:00']!
          .copyWith(status: SessionStatus.cancelled, modified: true);
      sessions.seed('g1', cancelled);

      final again = await ensure(groupId: 'g1', userId: 'ana');
      expect(again.value, 0);
      expect(sessions.sessions['g1']!['2026-03-08T19:00']!.status, SessionStatus.cancelled);
    });

    test('does nothing for a non-organizer or a group without a schedule', () async {
      expect((await ensure(groupId: 'g1', userId: 'bruno')).value, 0);
      groups.groups['g1'] = makeGroup();
      expect((await ensure(groupId: 'g1', userId: 'ana')).value, 0);
      expect(sessions.sessions['g1'] ?? {}, isEmpty);
    });
  });

  group('CreateOneOffSession', () {
    test('creates a modified session from the group defaults, organizer only', () async {
      final useCase = CreateOneOffSession(guard, sessions, RandomCodes(Random(1)));
      final start = DateTime.utc(2026, 3, 10, 22);

      expect((await useCase(groupId: 'g1', actingUserId: 'bruno', startsAt: start)).failure, isA<Unauthorized>());

      final session = (await useCase(groupId: 'g1', actingUserId: 'ana', startsAt: start, teamSize: 4)).value;
      expect(session.modified, isTrue);
      expect(session.teamSize, 4);
      expect(session.startsAt, start);
      expect(sessions.sessions['g1']!.containsKey(session.id), isTrue);
    });
  });

  group('CancelSession and EditSession', () {
    setUp(() async => ensure(groupId: 'g1', userId: 'ana'));

    test('cancelling marks the session cancelled and modified', () async {
      final result = await CancelSession(guard, sessions)(groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'ana');
      expect(result.isOk, isTrue);
      final stored = sessions.sessions['g1']!['2026-03-08T19:00']!;
      expect(stored.status, SessionStatus.cancelled);
      expect(stored.modified, isTrue);
    });

    test('a published session cannot be cancelled or edited', () async {
      final published = sessions.sessions['g1']!['2026-03-08T19:00']!.copyWith(status: SessionStatus.teamsPublished);
      sessions.seed('g1', published);
      expect(
        (await CancelSession(guard, sessions)(groupId: 'g1', sessionId: published.id, actingUserId: 'ana')).failure,
        isA<SessionAlreadyPublished>(),
      );
      expect(
        (await EditSession(guard, sessions)(groupId: 'g1', sessionId: published.id, actingUserId: 'ana', teamSize: 4)).failure,
        isA<SessionAlreadyPublished>(),
      );
    });

    test('editing changes team size and start, moves the window, and marks modified', () async {
      final newStart = DateTime.utc(2026, 3, 8, 22);
      final edited = (await EditSession(guard, sessions)(
        groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'ana', teamSize: 4, startsAt: newStart,
      )).value;
      expect(edited.teamSize, 4);
      expect(edited.startsAt, newStart);
      expect(edited.checkInOpensAt, DateTime.utc(2026, 3, 8, 21));
      expect(edited.modified, isTrue);
      expect(edited.id, '2026-03-08T19:00'); // the id never changes
    });

    test('only the organizer may cancel or edit', () async {
      expect(
        (await CancelSession(guard, sessions)(groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'bruno')).failure,
        isA<Unauthorized>(),
      );
    });
  });

  group('UpdateSchedule', () {
    test('rebuilds untouched future sessions and keeps edited ones and ones with check-ins', () async {
      await ensure(groupId: 'g1', userId: 'ana'); // Sundays Mar 1, 8, 15, 22
      sessions.seed('g1', sessions.sessions['g1']!['2026-03-15T19:00']!.copyWith(modified: true));
      sessions.checkIns['g1/2026-03-22T19:00'] = {
        'bruno': CheckIn(userId: 'bruno', checkedInAt: now, distanceMeters: 5),
      };

      const saturdays = Schedule(
        weekdays: {DateTime.saturday},
        startTime: LocalTime(10, 0),
        timezone: 'America/New_York',
      );
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      final result = await useCase(groupId: 'g1', actingUserId: 'ana', schedule: saturdays);

      expect(result.isOk, isTrue);
      expect(groups.groups['g1']!.schedule, saturdays);
      final ids = sessions.sessions['g1']!.keys.toSet();
      // Kept: the edited Mar 15 and the Mar 22 one with a check-in.
      expect(ids, containsAll(['2026-03-15T19:00', '2026-03-22T19:00']));
      // Removed: the untouched Sunday Mar 8.
      expect(ids, isNot(contains('2026-03-08T19:00')));
      // Added: the new Saturdays.
      expect(ids, containsAll(['2026-03-07T10:00', '2026-03-14T10:00', '2026-03-21T10:00', '2026-03-28T10:00']));
    });

    test('only the organizer can change the schedule', () async {
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      expect((await useCase(groupId: 'g1', actingUserId: 'bruno', schedule: null)).failure, isA<Unauthorized>());
    });

    test('removing the schedule deletes untouched future sessions and creates none', () async {
      await ensure(groupId: 'g1', userId: 'ana');
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      await useCase(groupId: 'g1', actingUserId: 'ana', schedule: null);
      expect(groups.groups['g1']!.schedule, isNull);
      expect(sessions.sessions['g1']!, isEmpty);
    });
  });
}
