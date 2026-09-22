import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/providers.dart';
import 'package:volley_teams/features/auth/domain/entities/app_user.dart';
import 'package:volley_teams/features/auth/presentation/providers.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/presentation/providers.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/presentation/providers.dart';

import 'fake_auth_repository.dart';
import 'fake_group_repository.dart';
import 'fake_location_provider.dart';
import 'fake_session_repository.dart';

const boss = AppUser(uid: 'boss', displayName: 'Boss');

/// Fakes for every port, wired into a [ProviderScope].
class Harness {
  Harness({AppUser? user = FakeAuthRepository.defaultUser, DateTime? now})
      : auth = FakeAuthRepository(signedIn: user),
        now = now ?? DateTime.utc(2026, 9, 22, 22);

  final FakeAuthRepository auth;
  final groups = FakeGroupRepository();
  final sessions = FakeSessionRepository();
  final location = FakeLocationProvider();
  DateTime now;

  List<Override> get overrides => [
        authRepositoryProvider.overrideWithValue(auth),
        groupRepositoryProvider.overrideWithValue(groups),
        sessionRepositoryProvider.overrideWithValue(sessions),
        locationServiceProvider.overrideWithValue(location),
        localTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
        clockProvider.overrideWithValue(() => now),
        randomProvider.overrideWithValue(Random(1)),
      ];

  /// Group `g1` (organizer "boss") with players ana, p1..p5 rated C/B/A/C/B
  /// (1 + (i-1) % 3), and one scheduled session `s1` that starts at [now]
  /// with teams of [teamSize].
  void seed({int teamSize = 3, Group? group}) {
    groups.groups['g1'] = group ??
        const Group(id: 'g1', name: 'Sunday Vôlei', organizerId: 'boss', inviteCode: 'ABCD2345', court: Coordinates(0, 0));
    groups.members['g1'] = {
      'boss': const Member(userId: 'boss', displayName: 'Boss', selfRating: 3, role: MemberRole.organizer),
      'ana': const Member(userId: 'ana', displayName: 'Ana', selfRating: 3, role: MemberRole.player),
      for (var i = 1; i <= 5; i++)
        'p$i': Member(
          userId: 'p$i', displayName: 'Player $i',
          selfRating: 1 + (i - 1) % 3, role: MemberRole.player,
        ),
    };
    sessions.sessions['g1'] = {
      's1': GameSession.scheduled(
        id: 's1', startsAt: now, teamSize: teamSize,
        court: const Coordinates(0, 0), radiusMeters: 150,
      ),
    };
  }

  Widget app(Widget home) => ProviderScope(overrides: overrides, child: MaterialApp(home: home));
}

/// Gives widgets room, so nothing needs scrolling in tests.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
