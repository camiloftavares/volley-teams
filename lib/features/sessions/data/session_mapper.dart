import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/geo.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';

Map<String, Object?> sessionToMap(GameSession session) => {
      'startsAt': Timestamp.fromDate(session.startsAt),
      'teamSize': session.teamSize,
      'courtLat': session.court.latitude,
      'courtLng': session.court.longitude,
      'radiusMeters': session.radiusMeters,
      'checkInOpensAt': Timestamp.fromDate(session.checkInOpensAt),
      'checkInClosesAt': Timestamp.fromDate(session.checkInClosesAt),
      'status': session.status.name,
      'modified': session.modified,
      'teams': [for (final team in session.teams) teamToMap(team)],
    };

GameSession sessionFromMap(String id, Map<String, dynamic> data) => GameSession(
      id: id,
      startsAt: _utc(data['startsAt']),
      teamSize: (data['teamSize'] as num).toInt(),
      court: Coordinates(
        (data['courtLat'] as num).toDouble(),
        (data['courtLng'] as num).toDouble(),
      ),
      radiusMeters: (data['radiusMeters'] as num).toDouble(),
      checkInOpensAt: _utc(data['checkInOpensAt']),
      checkInClosesAt: _utc(data['checkInClosesAt']),
      status: SessionStatus.values.byName(data['status'] as String),
      modified: data['modified'] as bool? ?? false,
      teams: [
        for (final team in (data['teams'] as List? ?? const []))
          teamFromMap(Map<String, dynamic>.from(team as Map)),
      ],
    );

Map<String, Object?> teamToMap(Team team) => {
      'index': team.index,
      'playerIds': team.playerIds,
      'ratingTotal': team.ratingTotal,
    };

Team teamFromMap(Map<String, dynamic> data) => Team(
      index: (data['index'] as num).toInt(),
      playerIds: [for (final id in data['playerIds'] as List) id as String],
      ratingTotal: (data['ratingTotal'] as num).toInt(),
    );

Map<String, Object?> checkInToMap(CheckIn checkIn) => {
      'checkedInAt': Timestamp.fromDate(checkIn.checkedInAt),
      'distanceMeters': checkIn.distanceMeters,
    };

CheckIn checkInFromMap(String userId, Map<String, dynamic> data) => CheckIn(
      userId: userId,
      checkedInAt: _utc(data['checkedInAt']),
      distanceMeters: (data['distanceMeters'] as num).toDouble(),
    );

DateTime _utc(Object? timestamp) => (timestamp as Timestamp).toDate().toUtc();
