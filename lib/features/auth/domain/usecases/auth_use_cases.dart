import '../../../../core/result.dart';
import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

class SignInWithGoogle {
  SignInWithGoogle(this._auth);

  final AuthRepository _auth;

  Future<Result<AppUser>> call() => _auth.signInWithGoogle();
}

class SignOut {
  SignOut(this._auth);

  final AuthRepository _auth;

  Future<void> call() => _auth.signOut();
}

class WatchAuthState {
  WatchAuthState(this._auth);

  final AuthRepository _auth;

  Stream<AppUser?> call() => _auth.watchUser();
}
