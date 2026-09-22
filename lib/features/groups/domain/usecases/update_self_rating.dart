import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class UpdateSelfRating {
  UpdateSelfRating(this._groups);

  final GroupRepository _groups;

  Future<Result<void>> call({
    required String groupId,
    required String userId,
    required int rating,
  }) {
    if (!isValidRating(rating)) {
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 3')));
    }
    return _groups.updateSelfRating(groupId, userId, rating);
  }
}
