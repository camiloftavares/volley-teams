import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/presentation/session_screen.dart';

import '../../../support/app_harness.dart';

Future<void> pumpSession(WidgetTester tester, Harness h) async {
  useTallScreen(tester);
  await tester.pumpWidget(h.app(const SessionScreen(groupId: 'g1', sessionId: 's1')));
  await tester.pumpAndSettle();
}

void checkInPlayers(Harness h, Iterable<String> ids) {
  h.sessions.checkIns['g1/s1'] = {
    for (final id in ids) id: CheckIn(userId: id, checkedInAt: h.now, distanceMeters: 5),
  };
}

void main() {
  group('player check-in', () {
    testWidgets('inside the geofence the player is checked in', (tester) async {
      final h = Harness()..seed();
      h.location.position = const DevicePosition(coordinates: Coordinates(0.0005, 0)); // ~55 m
      await pumpSession(tester, h);

      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();

      expect(find.text("You're checked in"), findsOneWidget);
      expect(find.text('Check out'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1']!.keys, ['ana']);
    });

    testWidgets('outside the geofence shows the distance and stays unchecked', (tester) async {
      final h = Harness()..seed();
      h.location.position = const DevicePosition(coordinates: Coordinates(0.002, 0)); // ~222 m
      await pumpSession(tester, h);

      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('from the court'), findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1'] ?? {}, isEmpty);
    });

    testWidgets('before the window opens there is no check-in button', (tester) async {
      final h = Harness()..seed();
      h.now = h.now.subtract(const Duration(hours: 2));
      await pumpSession(tester, h);

      expect(find.text('Check in'), findsNothing);
      expect(find.textContaining('Check-in opens at'), findsOneWidget);
    });

    testWidgets('a checked-in player can check out', (tester) async {
      final h = Harness()..seed();
      checkInPlayers(h, ['ana']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Check out'));
      await tester.pumpAndSettle();

      expect(find.text('Check in'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1']!, isEmpty);
    });
  });

  group('organizer', () {
    testWidgets('generates a preview, then publishes it', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1', 'p2', 'p3', 'p4', 'p5']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-0')), findsOneWidget);
      expect(find.byKey(const Key('team-1')), findsOneWidget);
      expect(find.text('Publish teams'), findsOneWidget);
      // A preview is not persisted.
      expect(h.sessions.sessions['g1']!['s1']!.status, SessionStatus.scheduled);

      await tester.tap(find.text('Publish teams'));
      await tester.pumpAndSettle();

      final stored = h.sessions.sessions['g1']!['s1']!;
      expect(stored.status, SessionStatus.teamsPublished);
      expect(stored.teams, hasLength(2));
      expect(find.text('Publish teams'), findsNothing);
      expect(find.text('Teams'), findsOneWidget);
      expect(find.byKey(const Key('team-0')), findsOneWidget);
    });

    testWidgets('swapping a check-in after the draw flags the preview as stale', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1', 'p2', 'p3', 'p4', 'p5']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-0')), findsOneWidget);
      expect(find.textContaining('Check-ins changed since this draw'), findsNothing);

      // One player leaves and another arrives: the count stays at 6.
      await h.sessions.checkOut('g1', 's1', 'p5');
      await h.sessions.checkIn('g1', 's1', CheckIn(userId: 'boss', checkedInAt: h.now, distanceMeters: 5));
      await tester.pumpAndSettle();

      expect(h.sessions.checkIns['g1/s1']!, hasLength(6));
      expect(find.textContaining('Check-ins changed since this draw'), findsOneWidget);
    });

    testWidgets('with too few check-ins the organizer is told why', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only 2 checked in'), findsOneWidget);
      expect(find.byKey(const Key('team-0')), findsNothing);
    });

    testWidgets('the organizer removes a check-in; a player has no such button', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1']);
      await pumpSession(tester, h);

      await tester.tap(find.descendant(of: find.byKey(const Key('checkin-p1')), matching: find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(h.sessions.checkIns['g1/s1']!.keys, ['ana']);

      final player = Harness()..seed();
      checkInPlayers(player, ['p1']);
      await pumpSession(tester, player);
      expect(find.byTooltip('Remove check-in'), findsNothing);
      expect(find.text('Generate teams'), findsNothing);
    });

    testWidgets('cancelling asks for confirmation and marks the game cancelled', (tester) async {
      final h = Harness(user: boss)..seed();
      await pumpSession(tester, h);

      await tester.tap(find.text('Cancel game'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel game'));
      await tester.pumpAndSettle();

      expect(h.sessions.sessions['g1']!['s1']!.status, SessionStatus.cancelled);
      expect(find.text('This game was cancelled'), findsOneWidget);
    });
  });
}
