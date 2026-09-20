import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/random_codes.dart';

void main() {
  test('invite codes are 8 characters from the unambiguous alphabet', () {
    final codes = RandomCodes(Random(1));
    for (var i = 0; i < 50; i++) {
      final code = codes.inviteCode();
      expect(code, hasLength(RandomCodes.inviteLength));
      expect(code.split('').every(RandomCodes.inviteAlphabet.contains), isTrue);
    }
  });

  test('ids have the requested length and differ between calls', () {
    final codes = RandomCodes(Random(1));
    expect(codes.id(), hasLength(20));
    expect(codes.id(12), hasLength(12));
    expect(codes.id(), isNot(codes.id()));
  });
}
