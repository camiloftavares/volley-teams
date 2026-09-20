import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const hours = (n) => Timestamp.fromDate(new Date(Date.now() + n * 3600 * 1000));

let env;

before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-volley-teams',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host,
      port: Number(port),
    },
  });
});

after(async () => env.cleanup());

const member = (userId, role = 'player', extra = {}) => ({
  userId,
  displayName: userId,
  photoUrl: null,
  selfRating: 3,
  organizerOverride: null,
  role,
  ...extra,
});

const session = (extra = {}) => ({
  startsAt: hours(0),
  teamSize: 6,
  courtLat: 0,
  courtLng: 0,
  radiusMeters: 150,
  checkInOpensAt: hours(-1),
  checkInClosesAt: hours(3),
  status: 'scheduled',
  modified: false,
  teams: [],
  ...extra,
});

// g1: organizer "boss", player "ana". s1 = open window, s2 = opens later,
// s3 = already published, s4 = window already closed.
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'groups/g1'), { name: 'G', organizerId: 'boss', inviteCode: 'CODE2345' });
    await setDoc(doc(db, 'inviteCodes/CODE2345'), { groupId: 'g1', groupName: 'G' });
    await setDoc(doc(db, 'groups/g1/members/boss'), member('boss', 'organizer'));
    await setDoc(doc(db, 'groups/g1/members/ana'), member('ana'));
    await setDoc(doc(db, 'groups/g1/sessions/s1'), session());
    await setDoc(doc(db, 'groups/g1/sessions/s2'), session({ checkInOpensAt: hours(2), checkInClosesAt: hours(6) }));
    await setDoc(doc(db, 'groups/g1/sessions/s3'), session({ status: 'teamsPublished' }));
    await setDoc(doc(db, 'groups/g1/sessions/s4'), session({ checkInOpensAt: hours(-5), checkInClosesAt: hours(-1) }));
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

describe('groups and invite codes', () => {
  test('only members can read a group', async () => {
    await assertSucceeds(getDoc(doc(as('ana'), 'groups/g1')));
    await assertFails(getDoc(doc(as('eve'), 'groups/g1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'groups/g1')));
  });

  test('a signed-in user can get an invite code but never list codes', async () => {
    await assertSucceeds(getDoc(doc(as('eve'), 'inviteCodes/CODE2345')));
    await assertFails(getDocs(collection(as('eve'), 'inviteCodes')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'inviteCodes/CODE2345')));
  });

  test('creating a group writes group, invite code and organizer member in one batch', async () => {
    const db = as('zoe');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/g2'), { name: 'New', organizerId: 'zoe', inviteCode: 'NEWCODE2' });
    batch.set(doc(db, 'inviteCodes/NEWCODE2'), { groupId: 'g2', groupName: 'New' });
    batch.set(doc(db, 'groups/g2/members/zoe'), member('zoe', 'organizer'));
    await assertSucceeds(batch.commit());
  });

  test('the organizer member document must carry the creator\'s own userId', async () => {
    const db = as('zoe');
    const batch = writeBatch(db);
    batch.set(doc(db, 'groups/g2'), { name: 'New', organizerId: 'zoe', inviteCode: 'NEWCODE2' });
    batch.set(doc(db, 'inviteCodes/NEWCODE2'), { groupId: 'g2', groupName: 'New' });
    batch.set(doc(db, 'groups/g2/members/zoe'), member('ana', 'organizer'));
    await assertFails(batch.commit());
  });

  test('creating a group works as a read-free transaction (three sets)', async () => {
    const db = as('zoe');
    await assertSucceeds(
      runTransaction(db, async (tx) => {
        tx.set(doc(db, 'groups/g2'), { name: 'New', organizerId: 'zoe', inviteCode: 'NEWCODE2' });
        tx.set(doc(db, 'inviteCodes/NEWCODE2'), { groupId: 'g2', groupName: 'New' });
        tx.set(doc(db, 'groups/g2/members/zoe'), member('zoe', 'organizer'));
      }),
    );
  });

  test('a group cannot be created on behalf of someone else', async () => {
    await assertFails(setDoc(doc(as('zoe'), 'groups/g2'), { name: 'X', organizerId: 'boss', inviteCode: 'X' }));
  });

  test('an invite code cannot point at someone else\'s group', async () => {
    const db = as('eve');
    const batch = writeBatch(db);
    batch.set(doc(db, 'inviteCodes/HIJACK22'), { groupId: 'g1', groupName: 'G' });
    await assertFails(batch.commit());
  });

  test('only the organizer updates the group, and cannot hand it to someone else', async () => {
    await assertSucceeds(updateDoc(doc(as('boss'), 'groups/g1'), { radiusMeters: 200 }));
    await assertFails(updateDoc(doc(as('ana'), 'groups/g1'), { radiusMeters: 200 }));
    await assertFails(updateDoc(doc(as('boss'), 'groups/g1'), { organizerId: 'ana' }));
  });
});

describe('members', () => {
  const join = (uid, data) =>
    setDoc(doc(as(uid), `groups/g1/members/${uid}`), { ...member(uid), inviteCode: 'CODE2345', ...data });

  test('joining with a valid code and rating 1..5 works', async () => {
    await assertSucceeds(join('eve', {}));
    await assertSucceeds(join('bob', { selfRating: 1 }));
  });

  test('joining fails with a bad rating, a wrong code, an organizer role or an override', async () => {
    await assertFails(join('eve', { selfRating: 6 }));
    await assertFails(join('eve', { selfRating: 0 }));
    await assertFails(join('eve', { inviteCode: 'WRONG222' }));
    await assertFails(join('eve', { role: 'organizer' }));
    await assertFails(join('eve', { organizerOverride: 5 }));
  });

  // Mirrors joinByCode: read the code, read own member doc, create it if absent.
  const joinTransaction = (uid) => {
    const db = as(uid);
    return runTransaction(db, async (tx) => {
      await tx.get(doc(db, 'inviteCodes/CODE2345'));
      const existing = await tx.get(doc(db, `groups/g1/members/${uid}`));
      if (!existing.exists()) {
        tx.set(doc(db, `groups/g1/members/${uid}`), { ...member(uid), inviteCode: 'CODE2345' });
      }
    });
  };

  // withSecurityRulesDisabled resolves to void, so capture the snapshot in a closure.
  const readAsAdmin = async (path) => {
    let snap;
    await env.withSecurityRulesDisabled(async (ctx) => {
      snap = await getDoc(doc(ctx.firestore(), path));
    });
    return snap;
  };

  test('a non-member can join via a create-if-absent transaction', async () => {
    await assertSucceeds(joinTransaction('eve'));
    const snap = await readAsAdmin('groups/g1/members/eve');
    assert.equal(snap.exists(), true);
    assert.equal(snap.data().userId, 'eve');
  });

  test('re-joining as an existing member reads, does not write, and succeeds', async () => {
    const before = (await readAsAdmin('groups/g1/members/ana')).data();
    await assertSucceeds(joinTransaction('ana'));
    const after = (await readAsAdmin('groups/g1/members/ana')).data();
    assert.deepEqual(after, before);
  });

  test('a non-member cannot read other users\' member documents', async () => {
    await assertFails(getDoc(doc(as('eve'), 'groups/g1/members/ana')));
    await assertFails(getDoc(doc(as('eve'), 'groups/g1/members/boss')));
  });

  test('the userId field must match the document id', async () => {
    await assertFails(join('eve', { userId: 'ana' }));
  });

  test('nobody can join as somebody else', async () => {
    await assertFails(setDoc(doc(as('eve'), 'groups/g1/members/bob'), { ...member('bob'), inviteCode: 'CODE2345' }));
  });

  test('a member edits only their own selfRating', async () => {
    await assertSucceeds(updateDoc(doc(as('ana'), 'groups/g1/members/ana'), { selfRating: 5 }));
    await assertFails(updateDoc(doc(as('ana'), 'groups/g1/members/ana'), { selfRating: 9 }));
    await assertFails(updateDoc(doc(as('ana'), 'groups/g1/members/ana'), { role: 'organizer' }));
    await assertFails(updateDoc(doc(as('ana'), 'groups/g1/members/ana'), { organizerOverride: 5 }));
  });

  test('only the organizer sets organizerOverride, within 1..5, and can clear it', async () => {
    await assertSucceeds(updateDoc(doc(as('boss'), 'groups/g1/members/ana'), { organizerOverride: 2 }));
    await assertFails(updateDoc(doc(as('boss'), 'groups/g1/members/ana'), { organizerOverride: 7 }));
    await assertSucceeds(updateDoc(doc(as('boss'), 'groups/g1/members/ana'), { organizerOverride: null }));
    await assertFails(updateDoc(doc(as('boss'), 'groups/g1/members/ana'), { selfRating: 1 }));
  });

  test('a player can leave, the organizer can remove a player, nobody removes the organizer', async () => {
    await assertSucceeds(deleteDoc(doc(as('ana'), 'groups/g1/members/ana')));
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'groups/g1/members/ana'), member('ana')));
    await assertSucceeds(deleteDoc(doc(as('boss'), 'groups/g1/members/ana')));
    await assertFails(deleteDoc(doc(as('boss'), 'groups/g1/members/boss')));
  });

  test('"my groups" collection-group query works for your own memberships only', async () => {
    await assertSucceeds(getDocs(query(collectionGroup(as('ana'), 'members'), where('userId', '==', 'ana'))));
    await assertFails(getDocs(query(collectionGroup(as('ana'), 'members'), where('userId', '==', 'boss'))));
    await assertFails(getDocs(collectionGroup(as('ana'), 'members')));
  });
});

describe('sessions', () => {
  test('members read sessions, outsiders do not', async () => {
    await assertSucceeds(getDoc(doc(as('ana'), 'groups/g1/sessions/s1')));
    await assertFails(getDoc(doc(as('eve'), 'groups/g1/sessions/s1')));
  });

  test('only the organizer creates, edits and deletes sessions', async () => {
    await assertSucceeds(setDoc(doc(as('boss'), 'groups/g1/sessions/new'), session()));
    await assertFails(setDoc(doc(as('ana'), 'groups/g1/sessions/new2'), session()));
    await assertFails(updateDoc(doc(as('ana'), 'groups/g1/sessions/s1'), { teamSize: 4 }));
    await assertSucceeds(updateDoc(doc(as('boss'), 'groups/g1/sessions/s1'), { teamSize: 4 }));
    await assertSucceeds(deleteDoc(doc(as('boss'), 'groups/g1/sessions/s2')));
    await assertFails(deleteDoc(doc(as('ana'), 'groups/g1/sessions/s1')));
  });

  test('a session must be created as scheduled', async () => {
    await assertFails(setDoc(doc(as('boss'), 'groups/g1/sessions/x'), session({ status: 'teamsPublished' })));
  });

  test('teams are published only from scheduled', async () => {
    const teams = [{ index: 0, playerIds: ['ana'], ratingTotal: 3 }];
    await assertSucceeds(updateDoc(doc(as('boss'), 'groups/g1/sessions/s1'), { status: 'teamsPublished', teams }));
    await assertFails(updateDoc(doc(as('boss'), 'groups/g1/sessions/s3'), { status: 'teamsPublished', teams }));
  });
});

describe('check-ins', () => {
  const checkIn = (uid, sessionId = 's1') =>
    setDoc(doc(as(uid), `groups/g1/sessions/${sessionId}/checkins/${uid}`), {
      checkedInAt: Timestamp.now(),
      distanceMeters: 12,
    });

  test('a member can check in while the window is open', async () => {
    await assertSucceeds(checkIn('ana'));
  });

  test('cannot check in before the window opens or after teams are published', async () => {
    await assertFails(checkIn('ana', 's2'));
    await assertFails(checkIn('ana', 's3'));
  });

  test('cannot check in after the window has closed', async () => {
    await assertFails(checkIn('ana', 's4'));
  });

  test('cannot check in another user, or as a non-member', async () => {
    await assertFails(setDoc(doc(as('ana'), 'groups/g1/sessions/s1/checkins/boss'), { checkedInAt: Timestamp.now(), distanceMeters: 1 }));
    await assertFails(checkIn('eve'));
  });

  test('members read check-ins; outsiders do not', async () => {
    await assertSucceeds(checkIn('ana'));
    await assertSucceeds(getDocs(collection(as('boss'), 'groups/g1/sessions/s1/checkins')));
    await assertFails(getDocs(collection(as('eve'), 'groups/g1/sessions/s1/checkins')));
  });

  test('a player checks out; only the organizer removes someone else', async () => {
    await assertSucceeds(checkIn('ana'));
    await assertFails(deleteDoc(doc(as('eve'), 'groups/g1/sessions/s1/checkins/ana')));
    await assertSucceeds(deleteDoc(doc(as('boss'), 'groups/g1/sessions/s1/checkins/ana')));
    await assertSucceeds(checkIn('ana'));
    await assertSucceeds(deleteDoc(doc(as('ana'), 'groups/g1/sessions/s1/checkins/ana')));
  });
});
