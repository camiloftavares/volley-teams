import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';

void main() {
  final start = DateTime.utc(2026, 9, 22, 22);
  final session = GameSession.scheduled(
    id: '2026-09-22T19:00',
    startsAt: start,
    teamSize: 6,
    court: const Coordinates(0, 0),
    radiusMeters: 150,
  );

  test('check-in window is 60 minutes before to 3 hours after the start', () {
    expect(session.checkInOpensAt, DateTime.utc(2026, 9, 22, 21));
    expect(session.checkInClosesAt, DateTime.utc(2026, 9, 23, 1));
  });

  test('check-in is open only inside the window', () {
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 22, 20, 59)), isFalse);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 22, 21)), isTrue);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 23, 1)), isTrue);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 23, 1, 1)), isFalse);
  });

  test('check-in is closed once published or cancelled', () {
    final inside = DateTime.utc(2026, 9, 22, 22);
    expect(
      session.copyWith(status: SessionStatus.teamsPublished).isCheckInOpen(inside),
      isFalse,
    );
    expect(
      session.copyWith(status: SessionStatus.cancelled).isCheckInOpen(inside),
      isFalse,
    );
  });

  test('moving the start moves the window', () {
    final moved = session.copyWith(startsAt: DateTime.utc(2026, 9, 22, 23));
    expect(moved.checkInOpensAt, DateTime.utc(2026, 9, 22, 22));
  });

  test('team average is total divided by size', () {
    const team = Team(index: 0, playerIds: ['a', 'b', 'c'], ratingTotal: 7);
    expect(team.averageRating, closeTo(2.333, 0.001));
  });
}
