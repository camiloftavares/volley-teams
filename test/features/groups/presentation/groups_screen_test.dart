import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/app/app.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/presentation/group_detail_screen.dart';
import 'package:volley_teams/features/groups/presentation/groups_screen.dart';

import '../../../support/app_harness.dart';

Finder inAppBar(String text) => find.descendant(of: find.byType(AppBar), matching: find.text(text));

Future<void> pumpApp(WidgetTester tester, Harness h) async {
  useTallScreen(tester);
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const VolleyApp()));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('creating a group stores it at the current position and opens it', (tester) async {
    final h = Harness();
    h.location.position = const DevicePosition(coordinates: Coordinates(51.5, -0.12));
    await pumpApp(tester, h);
    expect(find.text('You are not in a group yet.\nCreate one, or join with an invite code.'), findsOneWidget);

    await tester.tap(find.byTooltip('Create a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Beach Crew');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final group = h.groups.groups.values.single;
    expect(group.name, 'Beach Crew');
    expect(group.organizerId, 'ana');
    expect(group.court, const Coordinates(51.5, -0.12));
    expect(h.groups.members[group.id]!['ana']!.role, MemberRole.organizer);

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(inAppBar('Beach Crew'), findsOneWidget);
  });

  testWidgets('joining with a valid code (any case) adds the user as a player and opens the group',
      (tester) async {
    final h = Harness();
    h.groups.groups['g2'] = const Group(
      id: 'g2', name: 'Friday Crew', organizerId: 'boss', inviteCode: 'JOINCODE', court: Coordinates(0, 0),
    );
    h.groups.members['g2'] = {
      'boss': const Member(userId: 'boss', displayName: 'Boss', selfRating: 3, role: MemberRole.organizer),
    };
    await pumpApp(tester, h);
    expect(h.groups.members['g2']!.containsKey('ana'), isFalse);

    await tester.tap(find.byTooltip('Join with a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'joincode');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();

    final ana = h.groups.members['g2']!['ana'];
    expect(ana, isNotNull);
    expect(ana!.role, MemberRole.player);
    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(inAppBar('Friday Crew'), findsOneWidget);
  });

  testWidgets('joining with an unknown code shows the friendly message and stays on My groups',
      (tester) async {
    final h = Harness()..seed();
    await pumpApp(tester, h);

    await tester.tap(find.byTooltip('Join with a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NOSUCHCODE');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();

    expect(find.text('That invite code does not exist.'), findsOneWidget);
    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.byType(GroupsScreen), findsOneWidget);
  });
}
