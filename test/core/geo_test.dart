import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';

void main() {
  test('distance between identical points is zero', () {
    const p = Coordinates(-23.55, -46.63);
    expect(distanceMeters(p, p), 0);
  });

  test('one degree of longitude at the equator is about 111.2 km', () {
    expect(
      distanceMeters(const Coordinates(0, 0), const Coordinates(0, 1)),
      closeTo(111195, 10),
    );
  });

  test('a 100 m offset north is measured as about 100 m', () {
    // 100 m of latitude is 100 / 111195 degrees.
    final d = distanceMeters(
      const Coordinates(40, -74),
      const Coordinates(40 + 100 / 111195, -74),
    );
    expect(d, closeTo(100, 0.5));
  });
}
