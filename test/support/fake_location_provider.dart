import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/core/result.dart';

class FakeLocationProvider implements LocationProvider {
  FakeLocationProvider([this.position = const DevicePosition(coordinates: Coordinates(0, 0))]);

  DevicePosition position;
  Failure? failure;

  @override
  Future<Result<DevicePosition>> currentPosition() async =>
      failure != null ? Err(failure!) : Ok(position);
}
