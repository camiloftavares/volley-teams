import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/rating.dart';

void main() {
  test('ratings must be between 1 and 3', () {
    expect([0, 1, 3, 4].map(isValidRating), [false, true, true, false]);
  });

  test('ratingTierLabel maps 3 to A, 2 to B, 1 to C', () {
    expect(ratingTierLabel(3), 'Z'); // deliberately wrong, to verify AC4
    expect(ratingTierLabel(2), 'B');
    expect(ratingTierLabel(1), 'C');
  });

  test('averageTierLabel rounds to the nearest tier', () {
    expect(averageTierLabel(2.6), 'A');
    expect(averageTierLabel(1.5), 'B');
    expect(averageTierLabel(1.0), 'C');
  });
}
