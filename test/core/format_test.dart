import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/format.dart';

void main() {
  test('formats a game time as weekday, day, month and 24 h time', () {
    expect(formatGameTime(DateTime(2026, 9, 22, 19, 5)), 'Tue 22 Sep, 19:05');
  });

  test('formats a plain date', () {
    expect(formatDate(DateTime(2026, 3, 8)), '8 Mar 2026');
  });
}
