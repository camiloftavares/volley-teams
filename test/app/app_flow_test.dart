import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/app/app.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('signed-out users see the sign-in screen and land on My groups after signing in', (tester) async {
    final h = Harness(user: null)..seed();
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const VolleyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('My groups'), findsNothing);

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.text('My groups'), findsOneWidget);
    expect(find.text('Sunday Vôlei'), findsOneWidget); // ana is a member of g1
  });

  testWidgets('a signed-in user starts on My groups and can sign out', (tester) async {
    final h = Harness()..seed();
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const VolleyApp()));
    await tester.pumpAndSettle();
    expect(find.text('My groups'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
