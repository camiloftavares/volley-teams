import '../entities/check_in.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class WatchUpcomingSessions {
  WatchUpcomingSessions(this._sessions);

  final SessionRepository _sessions;

  Stream<List<GameSession>> call(String groupId) => _sessions.watchUpcomingSessions(groupId);
}

class WatchSession {
  WatchSession(this._sessions);

  final SessionRepository _sessions;

  Stream<GameSession?> call(String groupId, String sessionId) =>
      _sessions.watchSession(groupId, sessionId);
}

class WatchCheckIns {
  WatchCheckIns(this._sessions);

  final SessionRepository _sessions;

  Stream<List<CheckIn>> call(String groupId, String sessionId) =>
      _sessions.watchCheckIns(groupId, sessionId);
}
