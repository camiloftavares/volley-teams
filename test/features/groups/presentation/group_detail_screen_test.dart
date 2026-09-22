import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/groups/presentation/group_detail_screen.dart';

import '../../../support/app_harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('opening a group as organizer creates the scheduled games', (tester) async {
    useTallScreen(tester);
    // 2026-03-01 12:00 UTC is a Sunday morning in New York.
    final h = Harness(user: boss, now: DateTime.utc(2026, 3, 1, 12))
      ..seed(
        group: Group(
          id: 'g1', name: 'Sunday Vôlei', organizerId: 'boss', inviteCode: 'ABCD2345',
          court: const Coordinates(0, 0),
          schedule: const Schedule(
            weekdays: {DateTime.sunday},
            startTime: LocalTime(19, 0),
            timezone: 'America/New_York',
          ),
        ),
      );
    h.sessions.sessions['g1'] = {};

    await tester.pumpWidget(h.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();

    expect(h.sessions.sessions['g1']!.keys,
        ['2026-03-01T19:00', '2026-03-08T19:00', '2026-03-15T19:00', '2026-03-22T19:00']);
    expect(find.byKey(const Key('session-2026-03-08T19:00')), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  testWidgets('the organizer sees organizer actions; a plain player does not', (tester) async {
    useTallScreen(tester);
    final organizer = Harness(user: boss)..seed();
    await tester.pumpWidget(organizer.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('One-off game'), findsOneWidget);

    final player = Harness()..seed();
    await tester.pumpWidget(player.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byKey(const Key('member-p1')), findsOneWidget);
  });

  testWidgets('a player can change their own rating; the organizer can override anyone', (tester) async {
    useTallScreen(tester);
    final h = Harness(user: boss)..seed();
    await tester.pumpWidget(h.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();

    // Organizer taps Player 1 (self-rated C) and sets an override of A.
    await tester.tap(find.byKey(const Key('member-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(h.groups.members['g1']!['p1']!.organizerOverride, 3);
    expect(h.groups.members['g1']!['p1']!.selfRating, 1);
    expect(find.textContaining('organizer set A'), findsOneWidget);
  });
}
