import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/check_in_to_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/check_out_of_session.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_location_provider.dart';
import '../../support/fake_session_repository.dart';

void main() {
  const court = Coordinates(0, 0);
  final start = DateTime.utc(2026, 9, 22, 22);
  late FakeSessionRepository sessions;
  late FakeLocationProvider location;
  late DateTime now;
  late CheckInToSession checkIn;

  setUp(() {
    now = DateTime.utc(2026, 9, 22, 21, 30); // inside the window
    sessions = FakeSessionRepository()
      ..seed(
        'g1',
        GameSession.scheduled(id: 's1', startsAt: start, teamSize: 6, court: court, radiusMeters: 150),
      );
    location = FakeLocationProvider();
    checkIn = CheckInToSession(sessions, location, () => now);
  });

  Future<dynamic> attempt() => checkIn(groupId: 'g1', sessionId: 's1', userId: 'ana');

  test('records the check-in with the measured distance when inside the radius', () async {
    // About 55 m north of the court.
    location.position = const DevicePosition(coordinates: Coordinates(0.0005, 0));
    final result = await attempt();
    expect(result.isOk, isTrue);
    expect(result.value.distanceMeters, closeTo(55.6, 1));
    expect(sessions.checkIns['g1/s1']!['ana'], isNotNull);
  });

  test('outside the radius fails with NotInGeofence and writes nothing', () async {
    location.position = const DevicePosition(coordinates: Coordinates(0.002, 0)); // ~222 m
    final result = await attempt();
    expect(result.failure, isA<NotInGeofence>());
    expect((result.failure as NotInGeofence).radiusMeters, 150);
    expect(sessions.checkIns['g1/s1'] ?? {}, isEmpty);
  });

  test('a mocked location is rejected', () async {
    location.position = const DevicePosition(coordinates: court, isMocked: true);
    expect((await attempt()).failure, isA<MockLocationDetected>());
  });

  test('a denied permission is passed through', () async {
    location.failure = const LocationPermissionDenied();
    expect((await attempt()).failure, isA<LocationPermissionDenied>());
  });

  test('before the window opens and after it closes, check-in is closed', () async {
    now = DateTime.utc(2026, 9, 22, 20, 59);
    expect((await attempt()).failure, isA<CheckInClosed>());
    now = DateTime.utc(2026, 9, 23, 1, 1);
    expect((await attempt()).failure, isA<CheckInClosed>());
  });

  test('a published or cancelled session is closed', () async {
    sessions.seed('g1', sessions.sessions['g1']!['s1']!.copyWith(status: SessionStatus.cancelled));
    expect((await attempt()).failure, isA<CheckInClosed>());
  });

  test('check-out removes the player; the organizer can remove anyone', () async {
    await attempt();
    await CheckOutOfSession(sessions)(groupId: 'g1', sessionId: 's1', userId: 'ana');
    expect(sessions.checkIns['g1/s1']!, isEmpty);

    await attempt();
    final groups = FakeGroupRepository()
      ..groups['g1'] = const Group(id: 'g1', name: 'G', organizerId: 'boss', inviteCode: 'X', court: court);
    final remove = RemoveCheckIn(OrganizerGuard(groups), sessions);
    expect((await remove(groupId: 'g1', sessionId: 's1', actingUserId: 'ana', targetUserId: 'ana')).failure, isA<Unauthorized>());
    expect((await remove(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', targetUserId: 'ana')).isOk, isTrue);
    expect(sessions.checkIns['g1/s1']!, isEmpty);
  });
}
