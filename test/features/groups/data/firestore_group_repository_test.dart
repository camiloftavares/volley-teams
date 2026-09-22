import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/data/firestore_group_repository.dart';
import 'package:volley_teams/features/groups/data/group_mapper.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';

const ana = Member(userId: 'ana', displayName: 'Ana', photoUrl: 'http://x/a.png', selfRating: 3, role: MemberRole.organizer);
const bruno = Member(userId: 'bruno', displayName: 'Bruno', selfRating: 3, role: MemberRole.player);

final sundayGroup = Group(
  id: 'g1',
  name: 'Sunday Vôlei',
  organizerId: 'ana',
  inviteCode: 'ABCD2345',
  court: const Coordinates(-23.5, -46.6),
  radiusMeters: 200,
  defaultTeamSize: 5,
  schedule: Schedule(
    weekdays: const {DateTime.tuesday, DateTime.thursday},
    startTime: const LocalTime(19, 30),
    endDate: DateTime(2026, 12, 31),
    timezone: 'America/Sao_Paulo',
  ),
);

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreGroupRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreGroupRepository(db);
  });

  group('mappers', () {
    test('a group with a schedule survives a round trip', () {
      expect(groupFromMap('g1', groupToMap(sundayGroup)), sundayGroup);
    });

    test('a group without a schedule survives a round trip', () {
      final plain = sundayGroup.copyWith(schedule: () => null);
      expect(groupFromMap('g1', groupToMap(plain)), plain);
    });

    test('a member survives a round trip, and the invite code is written only when given', () {
      expect(memberFromMap(memberToMap(bruno)), bruno);
      expect(memberToMap(bruno).containsKey('inviteCode'), isFalse);
      expect(memberToMap(bruno, inviteCode: 'X')['inviteCode'], 'X');
    });
  });

  group('createGroup', () {
    test('writes the group, its invite code and the organizer member', () async {
      expect((await repo.createGroup(sundayGroup, ana)).isOk, isTrue);
      expect((await db.doc('groups/g1').get()).exists, isTrue);
      expect((await db.doc('inviteCodes/ABCD2345').get()).data(), {'groupId': 'g1', 'groupName': 'Sunday Vôlei'});
      expect((await db.doc('groups/g1/members/ana').get()).data()!['role'], 'organizer');
    });

    test('watchMyGroups lists only the groups the user belongs to', () async {
      await repo.createGroup(sundayGroup, ana);
      await repo.createGroup(
        const Group(id: 'g2', name: 'Another', organizerId: 'bruno', inviteCode: 'ZZZZ2222', court: Coordinates(1, 1)),
        bruno,
      );

      final mine = await repo.watchMyGroups('ana').first;
      expect(mine.map((g) => g.id), ['g1']);
      expect((await repo.watchMyGroups('nobody').first), isEmpty);
    });
  });

  group('joinByCode', () {
    setUp(() => repo.createGroup(sundayGroup, ana));

    test('adds the member, storing the code used, and returns the group', () async {
      final result = await repo.joinByCode('ABCD2345', bruno);
      expect(result.value.id, 'g1');
      final stored = (await db.doc('groups/g1/members/bruno').get()).data()!;
      expect(stored['inviteCode'], 'ABCD2345');
      expect(stored['role'], 'player');
    });

    test('an unknown code fails with InvalidInviteCode', () async {
      expect((await repo.joinByCode('NOPE2222', bruno)).failure, isA<InvalidInviteCode>());
    });

    test('joining twice keeps the existing rating and override', () async {
      await repo.joinByCode('ABCD2345', bruno);
      await repo.setOrganizerOverride('g1', 'bruno', 2);
      await repo.joinByCode('ABCD2345', bruno.copyWith(selfRating: 2));
      final stored = memberFromMap((await db.doc('groups/g1/members/bruno').get()).data()!);
      expect(stored.selfRating, 3);
      expect(stored.organizerOverride, 2);
    });
  });

  group('members and settings', () {
    setUp(() async {
      await repo.createGroup(sundayGroup, ana);
      await repo.joinByCode('ABCD2345', bruno);
    });

    test('rating and override updates are visible to getMembers and watchMembers', () async {
      await repo.updateSelfRating('g1', 'bruno', 2);
      await repo.setOrganizerOverride('g1', 'bruno', 1);
      final members = (await repo.getMembers('g1')).value;
      final updated = members.firstWhere((m) => m.userId == 'bruno');
      expect(updated.selfRating, 2);
      expect(updated.effectiveRating, 1);

      await repo.setOrganizerOverride('g1', 'bruno', null);
      expect((await repo.watchMembers('g1').first).firstWhere((m) => m.userId == 'bruno').effectiveRating, 2);
    });

    test('updateGroup stores new settings and a removed schedule', () async {
      await repo.updateGroup(sundayGroup.copyWith(radiusMeters: 500, schedule: () => null));
      final stored = (await repo.getGroup('g1')).value;
      expect(stored.radiusMeters, 500);
      expect(stored.schedule, isNull);
    });

    test('getGroup on a missing group fails with NotFound', () async {
      expect((await repo.getGroup('missing')).failure, isA<NotFound>());
    });
  });
}
