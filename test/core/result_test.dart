import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/result.dart';

void main() {
  test('Ok exposes its value', () {
    const Result<int> r = Ok(3);
    expect(r.isOk, isTrue);
    expect(r.value, 3);
  });

  test('Err exposes its failure and can be re-wrapped', () {
    const Result<int> r = Err(CheckInClosed());
    expect(r.isErr, isTrue);
    expect(r.failure, isA<CheckInClosed>());
    final Result<String> other = r.castErr();
    expect(other.failure, isA<CheckInClosed>());
  });

  test('fold picks the right branch', () {
    const Result<int> ok = Ok(2);
    const Result<int> err = Err(Offline());
    expect(ok.fold((v) => 'ok $v', (f) => 'err'), 'ok 2');
    expect(err.fold((v) => 'ok', (f) => 'err ${f.runtimeType}'), 'err Offline');
  });
}
