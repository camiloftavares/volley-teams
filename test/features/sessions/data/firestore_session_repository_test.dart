import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/sessions/data/firestore_session_repository.dart';
import 'package:volley_teams/features/sessions/data/session_mapper.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';

GameSession session(String id, DateTime start) => GameSession.scheduled(
      id: id, startsAt: start, teamSize: 6,
      court: const Coordinates(1, 2), radiusMeters: 150,
    );

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  late FakeFirebaseFirestore db;
  late FirestoreSessionRepository repo;
  final s1 = session('s1', DateTime.utc(2026, 9, 22, 22));
  const teams = [
    Team(index: 0, playerIds: ['a', 'b'], ratingTotal: 7),
    Team(index: 1, playerIds: ['c', 'd'], ratingTotal: 6),
  ];

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreSessionRepository(db, clock: () => now);
  });

  test('a session with teams survives a mapper round trip', () {
    final published = s1.copyWith(status: SessionStatus.teamsPublished, teams: teams, modified: true);
    expect(sessionFromMap('s1', sessionToMap(published)), published);
  });

  test('createIfAbsent creates once and never overwrites', () async {
    expect((await repo.createIfAbsent('g1', s1)).value, isTrue);
    expect((await repo.createIfAbsent('g1', s1.copyWith(teamSize: 3))).value, isFalse);
    expect((await repo.getSession('g1', 's1')).value.teamSize, 6);
  });

  test('getSession on a missing session fails with NotFound', () async {
    expect((await repo.getSession('g1', 'nope')).failure, isA<NotFound>());
  });

  test('publishTeams stores teams once; then reports published or cancelled', () async {
    await repo.createIfAbsent('g1', s1);
    expect((await repo.publishTeams('g1', 's1', teams)).isOk, isTrue);
    final stored = (await repo.getSession('g1', 's1')).value;
    expect(stored.status, SessionStatus.teamsPublished);
    expect(stored.teams, teams);
    expect((await repo.publishTeams('g1', 's1', teams)).failure, isA<SessionAlreadyPublished>());

    await repo.createIfAbsent('g1', session('s2', DateTime.utc(2026, 9, 23, 22)));
    await repo.updateSession('g1', (await repo.getSession('g1', 's2')).value.copyWith(status: SessionStatus.cancelled));
    expect((await repo.publishTeams('g1', 's2', teams)).failure, isA<SessionCancelled>());
  });

  test('checkIn writes the check-in; a closed session refuses it', () async {
    await repo.createIfAbsent('g1', s1);
    final checkIn = CheckIn(userId: 'ana', checkedInAt: now, distanceMeters: 42.5);
    expect((await repo.checkIn('g1', 's1', checkIn)).isOk, isTrue);
    expect((await repo.getCheckIns('g1', 's1')).value, [checkIn]);

    await repo.updateSession('g1', s1.copyWith(status: SessionStatus.cancelled));
    expect((await repo.checkIn('g1', 's1', CheckIn(userId: 'bruno', checkedInAt: now, distanceMeters: 1))).failure, isA<CheckInClosed>());
    expect((await repo.getCheckIns('g1', 's1')).value.map((c) => c.userId), ['ana']);
  });

  test('checkOut removes the check-in', () async {
    await repo.createIfAbsent('g1', s1);
    await repo.checkIn('g1', 's1', CheckIn(userId: 'ana', checkedInAt: now, distanceMeters: 1));
    await repo.checkOut('g1', 's1', 'ana');
    expect((await repo.getCheckIns('g1', 's1')).value, isEmpty);
  });

  test('watchUpcomingSessions hides sessions that ended more than a day ago, in start order', () async {
    await repo.createIfAbsent('g1', session('old', DateTime.utc(2026, 9, 18, 22)));
    await repo.createIfAbsent('g1', session('later', DateTime.utc(2026, 9, 29, 22)));
    await repo.createIfAbsent('g1', s1);
    expect((await repo.watchUpcomingSessions('g1').first).map((s) => s.id), ['s1', 'later']);
  });

  test('getSessionsStartingAfter and deleteSession', () async {
    await repo.createIfAbsent('g1', s1);
    await repo.createIfAbsent('g1', session('later', DateTime.utc(2026, 9, 29, 22)));
    expect((await repo.getSessionsStartingAfter('g1', DateTime.utc(2026, 9, 25))).value.map((s) => s.id), ['later']);
    await repo.deleteSession('g1', 'later');
    expect((await repo.getSession('g1', 'later')).failure, isA<NotFound>());
  });
}
