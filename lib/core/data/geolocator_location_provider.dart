import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../failure.dart';
import '../geo.dart';
import '../location_provider.dart';
import '../result.dart';

class GeolocatorLocationProvider implements LocationProvider {
  @override
  Future<Result<DevicePosition>> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const Err(Unexpected('Location services are turned off'));
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const Err(LocationPermissionDenied());
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return Ok(DevicePosition(
        coordinates: Coordinates(position.latitude, position.longitude),
        isMocked: position.isMocked,
      ));
    } on TimeoutException {
      return const Err(Unexpected('Could not get a GPS fix. Try again outdoors.'));
    }
  }
}
