import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/result.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';
import 'package:volley_teams/features/sessions/domain/repositories/session_repository.dart';

import 'changes.dart';

class FakeSessionRepository implements SessionRepository {
  /// groupId -> sessionId -> session
  final Map<String, Map<String, GameSession>> sessions = {};

  /// "groupId/sessionId" -> userId -> check-in
  final Map<String, Map<String, CheckIn>> checkIns = {};
  final _changes = Changes();

  Map<String, GameSession> _of(String groupId) => sessions.putIfAbsent(groupId, () => {});

  Map<String, CheckIn> _checkInsOf(String groupId, String sessionId) =>
      checkIns.putIfAbsent('$groupId/$sessionId', () => {});

  List<GameSession> _sorted(String groupId) =>
      _of(groupId).values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// Test helper: adds a session directly.
  void seed(String groupId, GameSession session) {
    _of(groupId)[session.id] = session;
    _changes.notify();
  }

  @override
  Stream<List<GameSession>> watchUpcomingSessions(String groupId) =>
      _changes.watch(() => _sorted(groupId));

  @override
  Stream<GameSession?> watchSession(String groupId, String sessionId) =>
      _changes.watch(() => _of(groupId)[sessionId]);

  @override
  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId) =>
      _changes.watch(() => _checkInsOf(groupId, sessionId).values.toList());

  @override
  Future<Result<GameSession>> getSession(String groupId, String sessionId) async {
    final session = _of(groupId)[sessionId];
    return session == null ? const Err(NotFound('session')) : Ok(session);
  }

  @override
  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after) async =>
      Ok(_sorted(groupId).where((s) => s.startsAt.isAfter(after)).toList());

  @override
  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId) async =>
      Ok(_checkInsOf(groupId, sessionId).values.toList());

  @override
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session) async {
    if (_of(groupId).containsKey(session.id)) return const Ok(false);
    _of(groupId)[session.id] = session;
    _changes.notify();
    return const Ok(true);
  }

  @override
  Future<Result<void>> updateSession(String groupId, GameSession session) async {
    _of(groupId)[session.id] = session;
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> deleteSession(String groupId, String sessionId) async {
    _of(groupId).remove(sessionId);
    checkIns.remove('$groupId/$sessionId');
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams) async {
    final session = _of(groupId)[sessionId];
    if (session == null) return const Err(NotFound('session'));
    if (session.status == SessionStatus.teamsPublished) return const Err(SessionAlreadyPublished());
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());
    _of(groupId)[sessionId] = session.copyWith(status: SessionStatus.teamsPublished, teams: teams);
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn) async {
    final session = _of(groupId)[sessionId];
    if (session == null) return const Err(NotFound('session'));
    if (session.status != SessionStatus.scheduled) return const Err(CheckInClosed());
    _checkInsOf(groupId, sessionId)[checkIn.userId] = checkIn;
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> checkOut(String groupId, String sessionId, String userId) async {
    _checkInsOf(groupId, sessionId).remove(userId);
    _changes.notify();
    return const Ok<void>(null);
  }
}
