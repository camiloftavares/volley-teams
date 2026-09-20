import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';

abstract interface class GroupRepository {
  /// Groups the user belongs to.
  Stream<List<Group>> watchMyGroups(String userId);

  Stream<Group?> watchGroup(String groupId);

  Stream<List<Member>> watchMembers(String groupId);

  Future<Result<Group>> getGroup(String groupId);

  Future<Result<List<Member>>> getMembers(String groupId);

  /// Persists the group, its invite code and the organizer's member document.
  Future<Result<Group>> createGroup(Group group, Member organizer);

  /// Resolves [code] to a group and adds [member] to it.
  ///
  /// Joining is create-if-absent: if the user already has a member document it
  /// is left unchanged (rating, override and role are kept) and the group is
  /// still returned. Fails with `InvalidInviteCode` when the code is unknown.
  Future<Result<Group>> joinByCode(String code, Member member);

  Future<Result<void>> updateGroup(Group group);

  Future<Result<void>> updateSelfRating(String groupId, String userId, int rating);

  Future<Result<void>> setOrganizerOverride(String groupId, String userId, int? rating);
}
