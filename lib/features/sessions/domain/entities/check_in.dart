import 'package:equatable/equatable.dart';

class CheckIn extends Equatable {
  const CheckIn({
    required this.userId,
    required this.checkedInAt,
    required this.distanceMeters,
  });

  final String userId;
  final DateTime checkedInAt;
  final double distanceMeters;

  @override
  List<Object?> get props => [userId, checkedInAt, distanceMeters];
}
