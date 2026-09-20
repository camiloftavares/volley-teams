import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

/// Google sign-in through `google_sign_in` (7.x) exchanged for a Firebase
/// credential. `GoogleSignIn.instance.initialize` must have run (see main.dart).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._google);

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  @override
  Stream<AppUser?> watchUser() => _auth.authStateChanges().map(_toUser);

  @override
  Future<Result<AppUser>> signInWithGoogle() async {
    try {
      final account = await _google.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final user = _toUser((await _auth.signInWithCredential(credential)).user);
      return user == null ? const Err(Unexpected('Sign-in returned no user')) : Ok(user);
    } on GoogleSignInException catch (e) {
      return Err(e.code == GoogleSignInExceptionCode.canceled
          ? const Unauthorized('Sign-in cancelled')
          : Unexpected(e.description ?? e.code.name));
    } on FirebaseAuthException catch (e) {
      return Err(Unexpected(e.message ?? e.code));
    }
  }

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  AppUser? _toUser(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          displayName: user.displayName ?? user.email ?? 'Player',
          photoUrl: user.photoURL,
        );
}
