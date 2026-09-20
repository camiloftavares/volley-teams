import 'package:equatable/equatable.dart';

import '../../../../core/geo.dart';
import 'team.dart';

enum SessionStatus { scheduled, teamsPublished, cancelled }

class GameSession extends Equatable {
  const GameSession({
    required this.id,
    required this.startsAt,
    required this.teamSize,
    required this.court,
    required this.radiusMeters,
    required this.checkInOpensAt,
    required this.checkInClosesAt,
    required this.status,
    required this.modified,
    required this.teams,
  });

  /// A new, unmodified `scheduled` session. [startsAt] must be UTC.
  factory GameSession.scheduled({
    required String id,
    required DateTime startsAt,
    required int teamSize,
    required Coordinates court,
    required double radiusMeters,
    bool modified = false,
  }) {
    assert(startsAt.isUtc, 'startsAt must be UTC');
    return GameSession(
      id: id,
      startsAt: startsAt,
      teamSize: teamSize,
      court: court,
      radiusMeters: radiusMeters,
      checkInOpensAt: startsAt.subtract(checkInOpensBefore),
      checkInClosesAt: startsAt.add(checkInClosesAfter),
      status: SessionStatus.scheduled,
      modified: modified,
      teams: const [],
    );
  }

  static const checkInOpensBefore = Duration(minutes: 60);
  static const checkInClosesAfter = Duration(hours: 3);

  final String id;
  final DateTime startsAt;
  final int teamSize;
  final Coordinates court;
  final double radiusMeters;
  final DateTime checkInOpensAt;
  final DateTime checkInClosesAt;
  final SessionStatus status;

  /// True once the organizer edited or cancelled this occurrence, and for
  /// one-off sessions: the recurring schedule must not touch it.
  final bool modified;
  final List<Team> teams;

  bool isCheckInOpen(DateTime now) =>
      status == SessionStatus.scheduled &&
      !now.isBefore(checkInOpensAt) &&
      !now.isAfter(checkInClosesAt);

  GameSession copyWith({
    DateTime? startsAt,
    int? teamSize,
    SessionStatus? status,
    bool? modified,
    List<Team>? teams,
  }) {
    final start = startsAt ?? this.startsAt;
    return GameSession(
      id: id,
      startsAt: start,
      teamSize: teamSize ?? this.teamSize,
      court: court,
      radiusMeters: radiusMeters,
      checkInOpensAt: start.subtract(checkInOpensBefore),
      checkInClosesAt: start.add(checkInClosesAfter),
      status: status ?? this.status,
      modified: modified ?? this.modified,
      teams: teams ?? this.teams,
    );
  }

  @override
  List<Object?> get props => [
        id,
        startsAt,
        teamSize,
        court,
        radiusMeters,
        checkInOpensAt,
        checkInClosesAt,
        status,
        modified,
        teams,
      ];
}
