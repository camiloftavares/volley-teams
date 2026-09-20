import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/widgets/ui.dart';

Widget view(AsyncValue<int> value) => MaterialApp(
      home: Scaffold(body: AsyncValueView<int>(value: value, data: (n) => Text('value $n'))),
    );

void main() {
  testWidgets('shows the data', (tester) async {
    await tester.pumpWidget(view(const AsyncData(3)));
    expect(find.text('value 3'), findsOneWidget);
  });

  testWidgets('a Failure error shows its friendly message', (tester) async {
    await tester.pumpWidget(view(AsyncError(const Unauthorized(), StackTrace.empty)));
    expect(find.text('You are not allowed to do that.'), findsOneWidget);
    expect(find.textContaining('Unauthorized'), findsNothing);
  });

  testWidgets('an arbitrary error never prints the raw object', (tester) async {
    await tester.pumpWidget(view(AsyncError(
      Exception('[cloud_firestore/permission-denied] Missing or insufficient permissions.'),
      StackTrace.empty,
    )));
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });
}
