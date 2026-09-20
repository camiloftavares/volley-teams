import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_guard.dart';
import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';
import '../domain/repositories/session_repository.dart';
import 'session_mapper.dart';

class FirestoreSessionRepository implements SessionRepository {
  FirestoreSessionRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  CollectionReference<Map<String, dynamic>> _sessions(String groupId) =>
      _db.collection('groups').doc(groupId).collection('sessions');

  DocumentReference<Map<String, dynamic>> _session(String groupId, String sessionId) =>
      _sessions(groupId).doc(sessionId);

  CollectionReference<Map<String, dynamic>> _checkIns(String groupId, String sessionId) =>
      _session(groupId, sessionId).collection('checkins');

  @override
  Stream<List<GameSession>> watchUpcomingSessions(String groupId) {
    final cutoff = Timestamp.fromDate(_clock().subtract(const Duration(days: 1)));
    return _sessions(groupId)
        .where('checkInClosesAt', isGreaterThan: cutoff)
        .orderBy('checkInClosesAt')
        .snapshots()
        .map((s) => [for (final d in s.docs) sessionFromMap(d.id, d.data())]);
  }

  @override
  Stream<GameSession?> watchSession(String groupId, String sessionId) =>
      _session(groupId, sessionId)
          .snapshots()
          .map((d) => d.exists ? sessionFromMap(d.id, d.data()!) : null);

  @override
  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId) =>
      _checkIns(groupId, sessionId)
          .orderBy('checkedInAt')
          .snapshots()
          .map((s) => [for (final d in s.docs) checkInFromMap(d.id, d.data())]);

  @override
  Future<Result<GameSession>> getSession(String groupId, String sessionId) =>
      guardFirestoreResult(() async {
        final doc = await _session(groupId, sessionId).get();
        if (!doc.exists) return const Err(NotFound('session'));
        return Ok(sessionFromMap(doc.id, doc.data()!));
      });

  @override
  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after) =>
      guardFirestore(() async {
        final snapshot = await _sessions(groupId)
            .where('startsAt', isGreaterThan: Timestamp.fromDate(after))
            .get();
        return [for (final d in snapshot.docs) sessionFromMap(d.id, d.data())];
      });

  @override
  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId) =>
      guardFirestore(() async {
        final snapshot = await _checkIns(groupId, sessionId).get();
        return [for (final d in snapshot.docs) checkInFromMap(d.id, d.data())];
      });

  @override
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session) =>
      guardFirestore(() => _db.runTransaction<bool>((tx) async {
            final ref = _session(groupId, session.id);
            if ((await tx.get(ref)).exists) return false;
            tx.set(ref, sessionToMap(session));
            return true;
          }));

  @override
  Future<Result<void>> updateSession(String groupId, GameSession session) =>
      guardFirestore(() => _session(groupId, session.id).update(sessionToMap(session)));

  @override
  Future<Result<void>> deleteSession(String groupId, String sessionId) =>
      guardFirestore(() => _session(groupId, sessionId).delete());

  @override
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams) =>
      guardFirestoreResult(() => _db.runTransaction<Result<void>>((tx) async {
            final ref = _session(groupId, sessionId);
            final doc = await tx.get(ref);
            if (!doc.exists) return const Err(NotFound('session'));
            switch (SessionStatus.values.byName(doc.data()!['status'] as String)) {
              case SessionStatus.teamsPublished:
                return const Err(SessionAlreadyPublished());
              case SessionStatus.cancelled:
                return const Err(SessionCancelled());
              case SessionStatus.scheduled:
                tx.update(ref, {
                  'status': SessionStatus.teamsPublished.name,
                  'teams': [for (final team in teams) teamToMap(team)],
                });
                return const Ok<void>(null);
            }
          }));

  @override
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn) =>
      guardFirestoreResult(() => _db.runTransaction<Result<void>>((tx) async {
            final doc = await tx.get(_session(groupId, sessionId));
            if (!doc.exists) return const Err(NotFound('session'));
            if (doc.data()!['status'] != SessionStatus.scheduled.name) {
              return const Err(CheckInClosed());
            }
            tx.set(_checkIns(groupId, sessionId).doc(checkIn.userId), checkInToMap(checkIn));
            return const Ok<void>(null);
          }));

  @override
  Future<Result<void>> checkOut(String groupId, String sessionId, String userId) =>
      guardFirestore(() => _checkIns(groupId, sessionId).doc(userId).delete());
}
