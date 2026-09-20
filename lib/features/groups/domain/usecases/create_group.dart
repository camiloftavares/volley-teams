import '../../../../core/failure.dart';
import '../../../../core/geo.dart';
import '../../../../core/random_codes.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class CreateGroup {
  CreateGroup(this._groups, this._codes);

  final GroupRepository _groups;
  final RandomCodes _codes;

  /// [organizer] carries the creator's identity and self rating; its role is
  /// forced to organizer.
  Future<Result<Group>> call({
    required String name,
    required Coordinates court,
    required Member organizer,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value(const Err(InvalidInput('Name is required')));
    if (!isValidRating(organizer.selfRating)) {
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 5')));
    }
    final group = Group(
      id: _codes.id(),
      name: trimmed,
      organizerId: organizer.userId,
      inviteCode: _codes.inviteCode(),
      court: court,
    );
    return _groups.createGroup(
      group,
      Member(
        userId: organizer.userId,
        displayName: organizer.displayName,
        photoUrl: organizer.photoUrl,
        selfRating: organizer.selfRating,
        role: MemberRole.organizer,
      ),
    );
  }
}
