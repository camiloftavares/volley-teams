import '../../../../core/failure.dart';
import '../../../../core/geo.dart';
import '../../../../core/result.dart';
import '../repositories/group_repository.dart';
import 'organizer_guard.dart';

class UpdateGroupSettings {
  UpdateGroupSettings(this._groups, this._guard);

  final GroupRepository _groups;
  final OrganizerGuard _guard;

  Future<Result<void>> call({
    required String groupId,
    required String actingUserId,
    Coordinates? court,
    double? radiusMeters,
    int? defaultTeamSize,
  }) async {
    if (radiusMeters != null && radiusMeters <= 0) {
      return const Err(InvalidInput('Radius must be positive'));
    }
    if (defaultTeamSize != null && defaultTeamSize < 2) {
      return const Err(InvalidInput('A team needs at least 2 players'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _groups.updateGroup(guard.value.copyWith(
      court: court,
      radiusMeters: radiusMeters,
      defaultTeamSize: defaultTeamSize,
    ));
  }
}
