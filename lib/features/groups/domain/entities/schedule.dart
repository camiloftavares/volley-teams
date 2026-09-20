import 'package:equatable/equatable.dart';

class LocalTime extends Equatable {
  const LocalTime(this.hour, this.minute);

  final int hour;
  final int minute;

  @override
  List<Object?> get props => [hour, minute];
}

/// Weekly recurrence rule, expressed as wall-clock time in [timezone] so that
/// daylight-saving changes never shift a game by an hour.
class Schedule extends Equatable {
  const Schedule({
    required this.weekdays,
    required this.startTime,
    this.endDate,
    required this.timezone,
  });

  /// `DateTime.monday` (1) through `DateTime.sunday` (7).
  final Set<int> weekdays;
  final LocalTime startTime;

  /// Last local calendar day (inclusive) on which a game may occur. Only the
  /// year, month and day are used.
  final DateTime? endDate;

  /// IANA name, e.g. `America/New_York`.
  final String timezone;

  @override
  List<Object?> get props => [weekdays, startTime, endDate, timezone];
}
