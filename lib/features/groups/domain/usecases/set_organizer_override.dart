import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';
import 'organizer_guard.dart';

class SetOrganizerOverride {
  SetOrganizerOverride(this._groups, this._guard);

  final GroupRepository _groups;
  final OrganizerGuard _guard;

  /// Pass a null [rating] to clear the override.
  Future<Result<void>> call({
    required String groupId,
    required String actingUserId,
    required String targetUserId,
    required int? rating,
  }) async {
    if (rating != null && !isValidRating(rating)) {
      return const Err(InvalidInput('Rating must be between 1 and 5'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _groups.setOrganizerOverride(groupId, targetUserId, rating);
  }
}
