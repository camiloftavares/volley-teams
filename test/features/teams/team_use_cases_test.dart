import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/teams/domain/services/team_balancer.dart';
import 'package:volley_teams/features/teams/domain/usecases/generate_teams.dart';
import 'package:volley_teams/features/teams/domain/usecases/publish_teams.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_session_repository.dart';

void main() {
  final start = DateTime.utc(2026, 9, 22, 22);
  late FakeGroupRepository groups;
  late FakeSessionRepository sessions;
  late OrganizerGuard guard;

  Member player(String id, int rating, {int? override}) => Member(
        userId: id, displayName: id, selfRating: rating,
        organizerOverride: override, role: MemberRole.player,
      );

  GenerateTeams generate() => GenerateTeams(guard, groups, sessions, const TeamBalancer(), Random(5));

  setUp(() {
    groups = FakeGroupRepository()
      ..groups['g1'] = const Group(
        id: 'g1', name: 'G', organizerId: 'boss', inviteCode: 'X', court: Coordinates(0, 0),
      );
    groups.members['g1'] = {
      for (final m in [
        player('a', 5), player('b', 5), player('c', 3), player('d', 3),
        player('e', 1, override: 4), player('f', 2), player('g', 2), player('h', 1),
        player('absent', 5),
      ])
        m.userId: m,
    };
    guard = OrganizerGuard(groups);
    sessions = FakeSessionRepository()
      ..seed('g1', GameSession.scheduled(
        id: 's1', startsAt: start, teamSize: 4,
        court: const Coordinates(0, 0), radiusMeters: 150,
      ));
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
      sessions.checkIns.putIfAbsent('g1/s1', () => {})[id] =
          CheckIn(userId: id, checkedInAt: start, distanceMeters: 1);
    }
  });

  test('balances only players who checked in, using effective ratings', () async {
    final teams = (await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).value;
    expect(teams, hasLength(2));
    final ids = teams.expand((t) => t.playerIds).toSet();
    expect(ids, {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'}); // not 'absent'
    // The two 5s are on different teams.
    final teamOf = {for (final t in teams) for (final id in t.playerIds) id: t.index};
    expect(teamOf['a'], isNot(teamOf['b']));
    // 'e' is rated 1 but overridden to 4: the two totals reflect that.
    expect(teams.fold<int>(0, (s, t) => s + t.ratingTotal), 5 + 5 + 3 + 3 + 4 + 2 + 2 + 1);
  });

  test('only the organizer can generate, and fewer than four players is rejected', () async {
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'a')).failure, isA<Unauthorized>());
    sessions.checkIns['g1/s1'] = {
      for (final id in ['a', 'b', 'c']) id: CheckIn(userId: id, checkedInAt: start, distanceMeters: 1),
    };
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<NotEnoughPlayers>());
  });

  test('publishing stores the teams and closes the session; a second publish fails', () async {
    final teams = (await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).value;
    final publish = PublishTeams(guard, sessions);

    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'a', teams: teams)).failure, isA<Unauthorized>());
    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', teams: teams)).isOk, isTrue);
    final stored = sessions.sessions['g1']!['s1']!;
    expect(stored.status, SessionStatus.teamsPublished);
    expect(stored.teams, teams);

    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', teams: teams)).failure, isA<SessionAlreadyPublished>());
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<SessionAlreadyPublished>());
  });

  test('a cancelled session cannot generate teams', () async {
    sessions.seed('g1', sessions.sessions['g1']!['s1']!.copyWith(status: SessionStatus.cancelled));
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<SessionCancelled>());
  });
}
