import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';

void main() {
  const member = Member(
    userId: 'u1',
    displayName: 'Ana',
    selfRating: 4,
    role: MemberRole.player,
  );

  test('effective rating is the self rating when there is no override', () {
    expect(member.effectiveRating, 4);
  });

  test('effective rating prefers the organizer override', () {
    expect(member.copyWith(organizerOverride: () => 2).effectiveRating, 2);
  });

  test('an override can be cleared again', () {
    final overridden = member.copyWith(organizerOverride: () => 2);
    expect(overridden.copyWith(organizerOverride: () => null).effectiveRating, 4);
  });

  test('ratings must be between 1 and 5', () {
    expect([0, 1, 5, 6].map(isValidRating), [false, true, true, false]);
  });
}
