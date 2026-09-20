import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/groups/presentation/schedule_screen.dart';

import '../../../support/app_harness.dart';

void main() {
  testWidgets('the end-date picker opens for a schedule whose end date has passed', (tester) async {
    useTallScreen(tester);
    final h = Harness(user: boss)
      ..seed(
        group: Group(
          id: 'g1', name: 'Sunday Vôlei', organizerId: 'boss', inviteCode: 'ABCD2345',
          court: const Coordinates(0, 0),
          schedule: Schedule(
            weekdays: const {DateTime.sunday},
            startTime: const LocalTime(19, 0),
            endDate: DateTime(2020, 1, 1),
            timezone: 'America/New_York',
          ),
        ),
      );

    await tester.pumpWidget(h.app(const ScheduleScreen(groupId: 'g1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Repeat until (optional)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
