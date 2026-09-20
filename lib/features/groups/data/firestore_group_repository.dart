import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_guard.dart';
import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../domain/entities/group.dart';
import '../domain/entities/member.dart';
import '../domain/repositories/group_repository.dart';
import 'group_mapper.dart';

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _groups => _db.collection('groups');

  CollectionReference<Map<String, dynamic>> _members(String groupId) =>
      _groups.doc(groupId).collection('members');

  DocumentReference<Map<String, dynamic>> _inviteCode(String code) =>
      _db.collection('inviteCodes').doc(code);

  @override
  Stream<List<Group>> watchMyGroups(String userId) => _db
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .snapshots()
          .asyncMap((snapshot) async {
        final ids = {for (final doc in snapshot.docs) doc.reference.parent.parent!.id};
        final docs = await Future.wait(ids.map((id) => _groups.doc(id).get()));
        return [
          for (final doc in docs)
            if (doc.exists) groupFromMap(doc.id, doc.data()!),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  @override
  Stream<Group?> watchGroup(String groupId) => _groups
      .doc(groupId)
      .snapshots()
      .map((doc) => doc.exists ? groupFromMap(doc.id, doc.data()!) : null);

  @override
  Stream<List<Member>> watchMembers(String groupId) => _members(groupId).snapshots().map(
        (snapshot) => [for (final doc in snapshot.docs) memberFromMap(doc.data())]
          ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase())),
      );

  @override
  Future<Result<Group>> getGroup(String groupId) => guardFirestoreResult(() async {
        final doc = await _groups.doc(groupId).get();
        if (!doc.exists) return const Err(NotFound('group'));
        return Ok(groupFromMap(doc.id, doc.data()!));
      });

  @override
  Future<Result<List<Member>>> getMembers(String groupId) => guardFirestore(() async {
        final snapshot = await _members(groupId).get();
        return [for (final doc in snapshot.docs) memberFromMap(doc.data())];
      });

  // Transactions (unlike batches) fail while offline instead of queueing.
  @override
  Future<Result<Group>> createGroup(Group group, Member organizer) =>
      guardFirestoreResult(() async {
        await _db.runTransaction((tx) async {
          tx.set(_groups.doc(group.id), groupToMap(group));
          tx.set(_inviteCode(group.inviteCode), {'groupId': group.id, 'groupName': group.name});
          tx.set(_members(group.id).doc(organizer.userId), memberToMap(organizer));
        });
        return Ok(group);
      });

  @override
  Future<Result<Group>> joinByCode(String code, Member member) async {
    final joined = await guardFirestoreResult<String>(
      () => _db.runTransaction<Result<String>>((tx) async {
        final codeDoc = await tx.get(_inviteCode(code));
        if (!codeDoc.exists) return const Err(InvalidInviteCode());
        final groupId = codeDoc.data()!['groupId'] as String;
        final memberRef = _members(groupId).doc(member.userId);
        // Joining twice must not overwrite the rating or an organizer override.
        if (!(await tx.get(memberRef)).exists) {
          tx.set(memberRef, memberToMap(member, inviteCode: code));
        }
        return Ok(groupId);
      }),
    );
    if (joined.isErr) return joined.castErr();
    // Readable only now that the caller is a member.
    return getGroup(joined.value);
  }

  @override
  Future<Result<void>> updateGroup(Group group) =>
      guardFirestore(() => _groups.doc(group.id).update(groupToMap(group)));

  @override
  Future<Result<void>> updateSelfRating(String groupId, String userId, int rating) =>
      guardFirestore(() => _members(groupId).doc(userId).update({'selfRating': rating}));

  @override
  Future<Result<void>> setOrganizerOverride(String groupId, String userId, int? rating) =>
      guardFirestore(() => _members(groupId).doc(userId).update({'organizerOverride': rating}));
}
