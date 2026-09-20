import '../../../../core/result.dart';
import '../entities/app_user.dart';

abstract interface class AuthRepository {
  /// Emits the signed-in user, or null when signed out.
  Stream<AppUser?> watchUser();

  Future<Result<AppUser>> signInWithGoogle();

  Future<void> signOut();
}
