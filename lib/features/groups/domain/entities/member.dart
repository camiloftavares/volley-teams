import 'package:equatable/equatable.dart';

const minRating = 1;
const maxRating = 5;

bool isValidRating(int rating) => rating >= minRating && rating <= maxRating;

enum MemberRole { organizer, player }

class Member extends Equatable {
  const Member({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.selfRating,
    this.organizerOverride,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final int selfRating;
  final int? organizerOverride;
  final MemberRole role;

  /// The rating the team balancer uses.
  int get effectiveRating => organizerOverride ?? selfRating;

  bool get isOrganizer => role == MemberRole.organizer;

  Member copyWith({int? selfRating, int? Function()? organizerOverride}) => Member(
        userId: userId,
        displayName: displayName,
        photoUrl: photoUrl,
        selfRating: selfRating ?? this.selfRating,
        organizerOverride:
            organizerOverride != null ? organizerOverride() : this.organizerOverride,
        role: role,
      );

  @override
  List<Object?> get props =>
      [userId, displayName, photoUrl, selfRating, organizerOverride, role];
}
