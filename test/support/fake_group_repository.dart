import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/result.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/repositories/group_repository.dart';

import 'changes.dart';

class FakeGroupRepository implements GroupRepository {
  final Map<String, Group> groups = {};

  /// groupId -> userId -> member
  final Map<String, Map<String, Member>> members = {};
  final _changes = Changes();

  @override
  Stream<List<Group>> watchMyGroups(String userId) => _changes.watch(() => [
        for (final entry in members.entries)
          if (entry.value.containsKey(userId)) groups[entry.key]!,
      ]);

  @override
  Stream<Group?> watchGroup(String groupId) => _changes.watch(() => groups[groupId]);

  @override
  Stream<List<Member>> watchMembers(String groupId) =>
      _changes.watch(() => (members[groupId] ?? {}).values.toList());

  @override
  Future<Result<Group>> getGroup(String groupId) async {
    final group = groups[groupId];
    return group == null ? const Err(NotFound('group')) : Ok(group);
  }

  @override
  Future<Result<List<Member>>> getMembers(String groupId) async =>
      Ok((members[groupId] ?? {}).values.toList());

  @override
  Future<Result<Group>> createGroup(Group group, Member organizer) async {
    groups[group.id] = group;
    members[group.id] = {organizer.userId: organizer};
    _changes.notify();
    return Ok(group);
  }

  @override
  Future<Result<Group>> joinByCode(String code, Member member) async {
    final match = groups.values.where((g) => g.inviteCode == code);
    if (match.isEmpty) return const Err(InvalidInviteCode());
    final group = match.first;
    members[group.id]![member.userId] = member;
    _changes.notify();
    return Ok(group);
  }

  @override
  Future<Result<void>> updateGroup(Group group) async {
    groups[group.id] = group;
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> updateSelfRating(String groupId, String userId, int rating) async {
    final member = members[groupId]?[userId];
    if (member == null) return const Err(NotFound('member'));
    members[groupId]![userId] = member.copyWith(selfRating: rating);
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> setOrganizerOverride(String groupId, String userId, int? rating) async {
    final member = members[groupId]?[userId];
    if (member == null) return const Err(NotFound('member'));
    members[groupId]![userId] = member.copyWith(organizerOverride: () => rating);
    _changes.notify();
    return const Ok<void>(null);
  }
}
