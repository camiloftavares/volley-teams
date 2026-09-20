import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/random_codes.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/usecases/create_group.dart';
import 'package:volley_teams/features/groups/domain/usecases/join_group_by_code.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/groups/domain/usecases/set_organizer_override.dart';
import 'package:volley_teams/features/groups/domain/usecases/update_group_settings.dart';
import 'package:volley_teams/features/groups/domain/usecases/update_self_rating.dart';

import '../../support/fake_group_repository.dart';

const ana = Member(userId: 'ana', displayName: 'Ana', selfRating: 4, role: MemberRole.player);
const bruno = Member(userId: 'bruno', displayName: 'Bruno', selfRating: 3, role: MemberRole.player);
const court = Coordinates(10, 20);

void main() {
  late FakeGroupRepository repo;
  late CreateGroup createGroup;

  setUp(() {
    repo = FakeGroupRepository();
    createGroup = CreateGroup(repo, RandomCodes(Random(1)));
  });

  group('CreateGroup', () {
    test('creates the group with a fresh invite code and makes the creator organizer', () async {
      final result = await createGroup(name: '  Sunday Vôlei ', court: court, organizer: ana);
      final group = result.value;
      expect(group.name, 'Sunday Vôlei');
      expect(group.organizerId, 'ana');
      expect(group.inviteCode, hasLength(8));
      expect(group.defaultTeamSize, 6);
      expect(group.radiusMeters, 150);
      expect(repo.members[group.id]!['ana']!.role, MemberRole.organizer);
      expect(repo.members[group.id]!['ana']!.selfRating, 4);
    });

    test('rejects an empty name and an out-of-range rating', () async {
      expect((await createGroup(name: ' ', court: court, organizer: ana)).failure, isA<InvalidInput>());
      final bad = ana.copyWith(selfRating: 9);
      expect((await createGroup(name: 'X', court: court, organizer: bad)).failure, isA<InvalidInput>());
    });
  });

  group('JoinGroupByCode', () {
    test('joins with a valid code regardless of case and as a player', () async {
      final group = (await createGroup(name: 'G', court: court, organizer: ana)).value;
      final result = await JoinGroupByCode(repo)(code: ' ${group.inviteCode.toLowerCase()} ', member: bruno);
      expect(result.isOk, isTrue);
      expect(repo.members[group.id]!['bruno']!.role, MemberRole.player);
    });

    test('an unknown code fails with InvalidInviteCode', () async {
      expect((await JoinGroupByCode(repo)(code: 'ZZZZZZZZ', member: bruno)).failure, isA<InvalidInviteCode>());
    });

    test('a joiner cannot smuggle in an organizer role or override', () async {
      final group = (await createGroup(name: 'G', court: court, organizer: ana)).value;
      final sneaky = Member(
        userId: 'eve', displayName: 'Eve', selfRating: 5,
        organizerOverride: 5, role: MemberRole.organizer,
      );
      await JoinGroupByCode(repo)(code: group.inviteCode, member: sneaky);
      final stored = repo.members[group.id]!['eve']!;
      expect(stored.role, MemberRole.player);
      expect(stored.organizerOverride, isNull);
    });
  });

  group('ratings', () {
    late String groupId;
    setUp(() async {
      final group = (await createGroup(name: 'G', court: court, organizer: ana)).value;
      groupId = group.id;
      await JoinGroupByCode(repo)(code: group.inviteCode, member: bruno);
    });

    test('a member can change their own rating within 1..5', () async {
      expect((await UpdateSelfRating(repo)(groupId: groupId, userId: 'bruno', rating: 5)).isOk, isTrue);
      expect(repo.members[groupId]!['bruno']!.selfRating, 5);
      expect((await UpdateSelfRating(repo)(groupId: groupId, userId: 'bruno', rating: 0)).failure, isA<InvalidInput>());
    });

    test('only the organizer can set an override, and it changes the effective rating', () async {
      final useCase = SetOrganizerOverride(repo, OrganizerGuard(repo));
      final denied = await useCase(groupId: groupId, actingUserId: 'bruno', targetUserId: 'bruno', rating: 5);
      expect(denied.failure, isA<Unauthorized>());

      final allowed = await useCase(groupId: groupId, actingUserId: 'ana', targetUserId: 'bruno', rating: 1);
      expect(allowed.isOk, isTrue);
      expect(repo.members[groupId]!['bruno']!.effectiveRating, 1);

      await useCase(groupId: groupId, actingUserId: 'ana', targetUserId: 'bruno', rating: null);
      expect(repo.members[groupId]!['bruno']!.effectiveRating, 3);
    });
  });

  group('UpdateGroupSettings', () {
    test('organizer updates court, radius and team size; others are refused', () async {
      final group = (await createGroup(name: 'G', court: court, organizer: ana)).value;
      await JoinGroupByCode(repo)(code: group.inviteCode, member: bruno);
      final useCase = UpdateGroupSettings(repo, OrganizerGuard(repo));

      expect((await useCase(groupId: group.id, actingUserId: 'bruno', radiusMeters: 500)).failure, isA<Unauthorized>());
      expect((await useCase(groupId: group.id, actingUserId: 'ana', radiusMeters: -1)).failure, isA<InvalidInput>());

      await useCase(groupId: group.id, actingUserId: 'ana', radiusMeters: 300, defaultTeamSize: 4, court: const Coordinates(1, 2));
      final updated = repo.groups[group.id]!;
      expect(updated.radiusMeters, 300);
      expect(updated.defaultTeamSize, 4);
      expect(updated.court, const Coordinates(1, 2));
    });
  });
}
