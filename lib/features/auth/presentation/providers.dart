import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/usecases/auth_use_cases.dart';

/// Bound to the real implementation in `app/composition_root.dart`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('Override authRepositoryProvider in the composition root.'),
);

final signInWithGoogleProvider =
    Provider((ref) => SignInWithGoogle(ref.watch(authRepositoryProvider)));

final signOutProvider = Provider((ref) => SignOut(ref.watch(authRepositoryProvider)));

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => WatchAuthState(ref.watch(authRepositoryProvider))(),
);

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authStateProvider).valueOrNull);
