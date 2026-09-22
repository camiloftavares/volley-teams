import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class JoinGroupByCode {
  JoinGroupByCode(this._groups);

  final GroupRepository _groups;

  /// [member] carries the joiner's identity and self rating; its role is
  /// forced to player and any override is dropped.
  Future<Result<Group>> call({required String code, required Member member}) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return Future.value(const Err(InvalidInviteCode()));
    if (!isValidRating(member.selfRating)) {
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 3')));
    }
    return _groups.joinByCode(
      normalized,
      Member(
        userId: member.userId,
        displayName: member.displayName,
        photoUrl: member.photoUrl,
        selfRating: member.selfRating,
        role: MemberRole.player,
      ),
    );
  }
}
