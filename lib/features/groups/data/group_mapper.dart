import '../../../core/geo.dart';
import '../domain/entities/group.dart';
import '../domain/entities/member.dart';
import '../domain/entities/schedule.dart';

Map<String, Object?> groupToMap(Group group) => {
      'name': group.name,
      'organizerId': group.organizerId,
      'inviteCode': group.inviteCode,
      'courtLat': group.court.latitude,
      'courtLng': group.court.longitude,
      'radiusMeters': group.radiusMeters,
      'defaultTeamSize': group.defaultTeamSize,
      'schedule': group.schedule == null ? null : scheduleToMap(group.schedule!),
    };

Group groupFromMap(String id, Map<String, dynamic> data) => Group(
      id: id,
      name: data['name'] as String,
      organizerId: data['organizerId'] as String,
      inviteCode: data['inviteCode'] as String,
      court: Coordinates(
        (data['courtLat'] as num).toDouble(),
        (data['courtLng'] as num).toDouble(),
      ),
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? Group.standardRadiusMeters,
      defaultTeamSize: (data['defaultTeamSize'] as num?)?.toInt() ?? Group.standardTeamSize,
      schedule: data['schedule'] == null
          ? null
          : scheduleFromMap(Map<String, dynamic>.from(data['schedule'] as Map)),
    );

Map<String, Object?> scheduleToMap(Schedule schedule) {
  final end = schedule.endDate;
  return {
    'weekdays': schedule.weekdays.toList()..sort(),
    'startHour': schedule.startTime.hour,
    'startMinute': schedule.startTime.minute,
    // A plain calendar date, so no timezone can shift it.
    'endDate': end == null ? null : _dateString(end),
    'timezone': schedule.timezone,
  };
}

Schedule scheduleFromMap(Map<String, dynamic> data) {
  final end = data['endDate'] as String?;
  return Schedule(
    weekdays: {for (final d in data['weekdays'] as List) (d as num).toInt()},
    startTime: LocalTime(
      (data['startHour'] as num).toInt(),
      (data['startMinute'] as num).toInt(),
    ),
    endDate: end == null ? null : DateTime.parse(end),
    timezone: data['timezone'] as String,
  );
}

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [inviteCode] is written only when joining; Security Rules check it.
Map<String, Object?> memberToMap(Member member, {String? inviteCode}) => {
      'userId': member.userId,
      'displayName': member.displayName,
      'photoUrl': member.photoUrl,
      'selfRating': member.selfRating,
      'organizerOverride': member.organizerOverride,
      'role': member.role.name,
      'inviteCode': ?inviteCode,
    };

Member memberFromMap(Map<String, dynamic> data) => Member(
      userId: data['userId'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      selfRating: (data['selfRating'] as num).toInt(),
      organizerOverride: (data['organizerOverride'] as num?)?.toInt(),
      role: MemberRole.values.byName(data['role'] as String),
    );
