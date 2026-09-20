import '../../../../core/failure.dart';
import '../../../../core/geo.dart';
import '../../../../core/location_provider.dart';
import '../../../../core/result.dart';
import '../entities/check_in.dart';
import '../repositories/session_repository.dart';

class CheckInToSession {
  CheckInToSession(this._sessions, this._location, this._now);

  final SessionRepository _sessions;
  final LocationProvider _location;
  final DateTime Function() _now;

  Future<Result<CheckIn>> call({
    required String groupId,
    required String sessionId,
    required String userId,
  }) async {
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found.castErr();
    final session = found.value;
    if (!session.isCheckInOpen(_now())) return const Err(CheckInClosed());

    final position = await _location.currentPosition();
    if (position.isErr) return position.castErr();
    if (position.value.isMocked) return const Err(MockLocationDetected());

    final distance = distanceMeters(position.value.coordinates, session.court);
    if (distance > session.radiusMeters) {
      return Err(NotInGeofence(distanceMeters: distance, radiusMeters: session.radiusMeters));
    }

    final checkIn = CheckIn(
      userId: userId,
      checkedInAt: _now().toUtc(),
      distanceMeters: distance,
    );
    final written = await _sessions.checkIn(groupId, sessionId, checkIn);
    return written.isErr ? written.castErr() : Ok(checkIn);
  }
}
