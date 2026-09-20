import '../../../../core/result.dart';
import '../entities/check_in.dart';
import '../entities/game_session.dart';
import '../entities/team.dart';

abstract interface class SessionRepository {
  /// Sessions whose check-in window has not ended more than a day ago,
  /// ordered by start time.
  Stream<List<GameSession>> watchUpcomingSessions(String groupId);

  Stream<GameSession?> watchSession(String groupId, String sessionId);

  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId);

  Future<Result<GameSession>> getSession(String groupId, String sessionId);

  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after);

  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId);

  /// Writes [session] only when no document with its id exists.
  /// Returns true when it was created, false when it already existed.
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session);

  Future<Result<void>> updateSession(String groupId, GameSession session);

  Future<Result<void>> deleteSession(String groupId, String sessionId);

  /// Atomically stores [teams] and sets the status to `teamsPublished`.
  /// Fails with `SessionAlreadyPublished` or `SessionCancelled` when the
  /// session is not `scheduled`.
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams);

  /// Atomically records the check-in. Fails with `CheckInClosed` when the
  /// session is no longer `scheduled`.
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn);

  Future<Result<void>> checkOut(String groupId, String sessionId, String userId);
}
