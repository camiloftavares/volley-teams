import 'dart:math';

/// Generates document ids and invite codes from an injected [Random].
class RandomCodes {
  RandomCodes(this._random);

  /// 32 characters, no `I`, `O`, `0` or `1`, so codes are easy to read aloud.
  static const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const inviteLength = 8;
  static const _idAlphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final Random _random;

  String id([int length = 20]) => _pick(_idAlphabet, length);

  String inviteCode() => _pick(inviteAlphabet, inviteLength);

  String _pick(String alphabet, int length) => String.fromCharCodes(
        List.generate(
          length,
          (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
        ),
      );
}
