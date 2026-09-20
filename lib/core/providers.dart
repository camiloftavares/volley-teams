import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_provider.dart';
import 'random_codes.dart';

/// Overridden in tests with a fixed time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final randomProvider = Provider<Random>((ref) => Random.secure());

final randomCodesProvider =
    Provider<RandomCodes>((ref) => RandomCodes(ref.watch(randomProvider)));

/// Bound to the real implementation in `app/composition_root.dart`.
final locationServiceProvider = Provider<LocationProvider>(
  (ref) => throw UnimplementedError('Override locationServiceProvider in the composition root.'),
);

/// Returns the device's IANA timezone name. Bound in the composition root.
final localTimezoneProvider = Provider<Future<String> Function()>(
  (ref) => throw UnimplementedError('Override localTimezoneProvider in the composition root.'),
);
