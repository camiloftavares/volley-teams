import 'package:equatable/equatable.dart';

import '../../../../core/geo.dart';
import 'schedule.dart';

class Group extends Equatable {
  const Group({
    required this.id,
    required this.name,
    required this.organizerId,
    required this.inviteCode,
    required this.court,
    this.radiusMeters = standardRadiusMeters,
    this.defaultTeamSize = standardTeamSize,
    this.schedule,
  });

  static const standardRadiusMeters = 150.0;
  static const standardTeamSize = 6;

  final String id;
  final String name;
  final String organizerId;
  final String inviteCode;
  final Coordinates court;
  final double radiusMeters;
  final int defaultTeamSize;
  final Schedule? schedule;

  Group copyWith({
    Coordinates? court,
    double? radiusMeters,
    int? defaultTeamSize,
    Schedule? Function()? schedule,
  }) =>
      Group(
        id: id,
        name: name,
        organizerId: organizerId,
        inviteCode: inviteCode,
        court: court ?? this.court,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        defaultTeamSize: defaultTeamSize ?? this.defaultTeamSize,
        schedule: schedule != null ? schedule() : this.schedule,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        organizerId,
        inviteCode,
        court,
        radiusMeters,
        defaultTeamSize,
        schedule,
      ];
}
