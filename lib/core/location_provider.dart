import 'package:equatable/equatable.dart';

import 'geo.dart';
import 'result.dart';

class DevicePosition extends Equatable {
  const DevicePosition({required this.coordinates, this.isMocked = false});

  final Coordinates coordinates;

  /// True when the platform reports the fix as coming from a mock provider.
  final bool isMocked;

  @override
  List<Object?> get props => [coordinates, isMocked];
}

/// Reads the device position. Implemented in the data layer with `geolocator`.
abstract interface class LocationProvider {
  /// Fails with `LocationPermissionDenied` when permission is refused, or
  /// `Unexpected` when location services are off or no fix is available.
  Future<Result<DevicePosition>> currentPosition();
}
