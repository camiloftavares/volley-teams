import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../repositories/group_repository.dart';

/// Loads a group and checks that [userId] is its organizer.
class OrganizerGuard {
  OrganizerGuard(this._groups);

  final GroupRepository _groups;

  Future<Result<Group>> require(String groupId, String userId) async {
    final result = await _groups.getGroup(groupId);
    if (result.isErr) return result;
    if (result.value.organizerId != userId) {
      return const Err(Unauthorized('Only the organizer can do this'));
    }
    return result;
  }
}
