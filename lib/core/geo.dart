import 'dart:math';

import 'package:equatable/equatable.dart';

class Coordinates extends Equatable {
  const Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];
}

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two points (Haversine formula).
double distanceMeters(Coordinates a, Coordinates b) {
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final dLat = lat2 - lat1;
  final dLng = _radians(b.longitude - a.longitude);
  final h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * asin(min(1.0, sqrt(h)));
}

double _radians(double degrees) => degrees * pi / 180;
