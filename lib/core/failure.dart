/// Every expected way an operation can fail. Use cases return these inside a
/// `Result`; exceptions never cross layer boundaries.
sealed class Failure {
  const Failure([this.message]);

  final String? message;

  @override
  String toString() => message == null ? '$runtimeType' : '$runtimeType: $message';
}

final class NotInGeofence extends Failure {
  const NotInGeofence({required this.distanceMeters, required this.radiusMeters});

  final double distanceMeters;
  final double radiusMeters;
}

final class MockLocationDetected extends Failure {
  const MockLocationDetected();
}

final class LocationPermissionDenied extends Failure {
  const LocationPermissionDenied();
}

final class CheckInClosed extends Failure {
  const CheckInClosed();
}

final class SessionAlreadyPublished extends Failure {
  const SessionAlreadyPublished();
}

final class SessionCancelled extends Failure {
  const SessionCancelled();
}

final class InvalidInviteCode extends Failure {
  const InvalidInviteCode();
}

final class NotEnoughPlayers extends Failure {
  const NotEnoughPlayers({required this.have, required this.need});

  final int have;
  final int need;
}

final class Unauthorized extends Failure {
  const Unauthorized([super.message]);
}

final class Offline extends Failure {
  const Offline();
}

final class NotFound extends Failure {
  const NotFound(String super.message);
}

final class InvalidInput extends Failure {
  const InvalidInput(String super.message);
}

final class Unexpected extends Failure {
  const Unexpected(String super.message);
}
