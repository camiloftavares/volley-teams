import '../entities/group.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class WatchMyGroups {
  WatchMyGroups(this._groups);

  final GroupRepository _groups;

  Stream<List<Group>> call(String userId) => _groups.watchMyGroups(userId);
}

class WatchGroup {
  WatchGroup(this._groups);

  final GroupRepository _groups;

  Stream<Group?> call(String groupId) => _groups.watchGroup(groupId);
}

class WatchMembers {
  WatchMembers(this._groups);

  final GroupRepository _groups;

  Stream<List<Member>> call(String groupId) => _groups.watchMembers(groupId);
}
