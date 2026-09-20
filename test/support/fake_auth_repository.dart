import 'dart:async';

import 'package:volley_teams/core/result.dart';
import 'package:volley_teams/features/auth/domain/entities/app_user.dart';
import 'package:volley_teams/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? signedIn}) : _user = signedIn;

  static const defaultUser = AppUser(uid: 'ana', displayName: 'Ana');

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast(sync: true);

  @override
  Stream<AppUser?> watchUser() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<Result<AppUser>> signInWithGoogle() async {
    _user = defaultUser;
    _controller.add(_user);
    return const Ok(defaultUser);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}
