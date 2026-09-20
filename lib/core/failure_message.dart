import 'failure.dart';

/// User-facing text for each [Failure].
String failureMessage(Failure failure) => switch (failure) {
      NotInGeofence(:final distanceMeters, :final radiusMeters) =>
        'You are ${distanceMeters.round()} m from the court. '
            'Check-in works within ${radiusMeters.round()} m.',
      MockLocationDetected() => 'Mock locations are not allowed for check-in.',
      LocationPermissionDenied() =>
        'Location permission is needed to check in. Enable it in Settings.',
      CheckInClosed() => 'Check-in is closed for this game.',
      SessionAlreadyPublished() => 'Teams were already published.',
      SessionCancelled() => 'This game was cancelled.',
      InvalidInviteCode() => 'That invite code does not exist.',
      NotEnoughPlayers(:final have, :final need) =>
        'Only $have checked in. At least $need players are needed.',
      Unauthorized(:final message) => message ?? 'You are not allowed to do that.',
      Offline() => 'You seem to be offline. Try again with a connection.',
      NotFound(:final message) => 'Not found${message == null ? '' : ': $message'}.',
      InvalidInput(:final message) => message ?? 'That input is not valid.',
      Unexpected(:final message) => message ?? 'Something went wrong.',
    };
