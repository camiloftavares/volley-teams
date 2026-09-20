# Volleyball Team Manager — Design Spec

Date: 2026-09-20
Status: Draft for review
Working package name: `volley_teams` (changeable)

## 1. Purpose

A Flutter mobile app (Android + iOS) for organizing recreational volleyball game days. Players arrive at the court and check in with the app. The organizer then generates teams, balanced by player quality: the strongest players are never on the same team, and each team mixes strong and weaker players.

## 2. Decisions

| Topic | Decision |
|---|---|
| Authentication | Google sign-in (`firebase_auth` + `google_sign_in`) |
| Backend | Firebase, **client-only**: Auth + Firestore + Security Rules. No Cloud Functions. |
| Architecture | Clean Architecture, feature-first (Section 3) |
| Skill level | Players self-rate 1–5 when joining a group. The organizer may set an override per member. |
| Game day | Organizer opens a session, players check in, organizer generates then publishes teams |
| Team sizing | Organizer sets players per team; team count is derived from check-ins |
| Check-in | Invite code to join a group; GPS geofence check on every check-in |
| Recurrence | Weekly on chosen weekdays, plus one-off sessions |
| Balancing | Tier-stratified random draw with a swap pass (Section 6) |

## 3. Architecture

Feature-first structure with the three Clean Architecture layers inside each feature.

```
lib/
  core/            Result/Failure types, UseCase base, geo math, shared widgets
  features/
    auth/
    groups/
    sessions/      game days, recurrence, check-in
    teams/         balancing + persisted team assignment
      domain/        entities, repository interfaces, use cases (pure Dart)
      data/          Firestore DTOs + mappers, repository implementations
      presentation/  Riverpod notifiers, screens, widgets
  app/             composition root (provider wiring), router, theme
```

Dependency rule: `presentation -> domain <- data`.

- **Domain** is pure Dart with no Flutter or Firebase imports: entities, repository interfaces, service interfaces (`LocationProvider`), use cases, and the `TeamBalancer`.
- **Data** implements the interfaces with Firebase and `geolocator`. Firestore documents are mapped to domain entities and never leak upward.
- **Presentation** talks only to use cases, through Riverpod providers. The composition root in `app/` binds interfaces to implementations, so tests swap in fakes.
- **Errors:** use cases return `Result<T>` (a sealed success/failure type). Exceptions never cross layer boundaries.

Stack: Flutter (Dart 3), `flutter_riverpod` (no code generation), `go_router`, `firebase_core`, `firebase_auth`, `google_sign_in`, `cloud_firestore`, `geolocator`, `timezone` and `flutter_timezone`, `equatable` for entity equality. Dev: `flutter_test`, `fake_cloud_firestore`, `mocktail`, Firebase Emulator Suite with `@firebase/rules-unit-testing`.

## 4. Domain model

- **Group:** id, name, organizerId, inviteCode, court location (lat, lng), geofence radius in metres (default 150), default team size (default 6), optional `Schedule`.
- **Member:** userId, displayName, photoUrl, `selfRating` (1–5), `organizerOverride` (1–5, optional), role (`organizer` | `player`). The group creator is the organizer. Effective rating = `organizerOverride ?? selfRating`.
- **Schedule:** set of weekdays, local start time, optional end date, IANA timezone. Stored as wall-clock time in the group's timezone, so DST changes do not shift games.
- **GameSession:** id, startsAt (UTC), teamSize, court location + radius (snapshot from the group), `checkInOpensAt` (start minus 60 min), `checkInClosesAt` (start plus 3 h), status (`scheduled` | `teamsPublished` | `cancelled`), `modified` flag (set when the organizer edits this occurrence), `teams`.
- **CheckIn:** userId, checkedInAt, measured distance in metres.
- **Team:** index, player ids, rating total, average rating.

Check-in is open when status is `scheduled` and now is within `[checkInOpensAt, checkInClosesAt]`. Publishing teams or cancelling closes it.

## 5. Firestore layout and recurrence

```
groups/{groupId}                                  group + schedule
groups/{groupId}/members/{uid}                    ratings, role, name, photo
groups/{groupId}/sessions/{sessionId}             status, times, teams[]
groups/{groupId}/sessions/{sessionId}/checkins/{uid}
inviteCodes/{code}                                { groupId, groupName }
```

Teams live inside the session document, so publishing is one atomic write.

**Recurrence without a server.** Nothing can run a scheduled job, so the client creates occurrences:

- When an organizer opens a group, `EnsureUpcomingSessions` expands the `Schedule` into concrete sessions for the next 4 weeks (a single constant).
- Session ids are deterministic: the local date-time in the group's timezone, e.g. `2026-09-22T19:00`. Creation is a transaction that only writes if the document does not exist, so it is idempotent and never overwrites an edited or cancelled occurrence.
- Editing or cancelling one occurrence changes only that document (and sets `modified`). A cancelled occurrence stays as a `cancelled` document so it is not recreated.
- Editing the schedule removes future sessions that are `scheduled`, not `modified`, and have no check-ins, then regenerates them. Other sessions are left alone.
- One-off sessions are sessions created directly, with no schedule.
- Limitation: members only see sessions that already exist. If the organizer does not open the app for more than 4 weeks, no new games appear until they do.

## 6. Team balancing

`TeamBalancer` is a pure function of (players with effective ratings, team size, injected `Random`).

**Team count.** With `n` check-ins and target size `s`: `T = max(2, round(n / s))`. Fails with `NotEnoughPlayers` when `n < 4`. Team sizes differ by at most 1. Example (`s = 6`): 13 -> 7+6, 17 -> 6+6+5, 15 -> 5+5+5.

**Algorithm.**
1. Sort players by effective rating, highest first. Shuffle players with equal ratings.
2. Cut the list into tiers of `T` players. Tier 0 (the top `T`) are the "aces". The last tier may be partial, with `n mod T` players.
3. Shuffle within each tier and deal one player to each team. Players of a partial last tier go to random distinct teams.
4. Swap pass: try swapping two players of the **same tier** between two teams, and keep the swap only if it strictly reduces the spread of team **average** ratings (max minus min). Averages are used because team sizes can differ by one. Repeat until no swap improves, up to a fixed iteration cap.

**Guarantees (enforced by tests, including randomized property tests):**
- No team has two players from the same tier; in particular, no two aces share a team.
- Every checked-in player is assigned exactly once.
- Team sizes differ by at most 1.
- The swap pass never increases the spread.
- The same seed produces the same result.

"Good player" means the top `T` players of that session's roster. If there are more strong players than teams, some must share a team; the tier rule still spreads them as evenly as possible.

**Generate and publish.**
- `GenerateTeams` reads the check-ins and current member ratings, runs the balancer, and returns an in-memory preview. Nothing is persisted. The organizer can reshuffle for a new draw.
- `PublishTeams` writes the teams and sets status `teamsPublished` in one transaction. It fails if the session is already published or cancelled. Players see the result live through a snapshot listener.

## 7. Auth, joining and check-in

**Auth.** `SignInWithGoogle` plus a router guard that sends signed-out users to the sign-in screen. Display name and photo are stored on the member document; there is no separate users collection.

**Joining.** The player enters an invite code. The app reads `inviteCodes/{code}` (which holds `groupId` and `groupName`), then creates `members/{uid}` with the player's self-rating and the code used. The code is 8 random characters from an unambiguous alphabet. Clients may `get` a code but never list codes. The organizer cannot leave a group in v1.

**Check-in (`CheckIn` use case).**
1. Verify the session is `scheduled` and the window is open.
2. Get the position through `LocationProvider` (handles permission; returns a typed failure if denied).
3. Compute the Haversine distance (pure function in `core/`). Reject with `NotInGeofence` when it exceeds the radius, and `MockLocationDetected` when the platform reports a mocked location.
4. Write `checkins/{uid}` in a transaction. Check-out deletes the player's own document.
5. The organizer can remove anyone's check-in.

## 8. Security Rules

- **groups:** members read. Any signed-in user can create a group they own. Only the organizer updates or deletes.
- **inviteCodes:** `get` allowed for signed-in users, `list` denied. Created only by the owner of the referenced group (same batch as the group).
- **members:**
  - A player creates only their own document, with role `player`, ratings in 1–5, and an `inviteCode` whose `inviteCodes/{code}.groupId` matches the group. The group owner may create their own `organizer` document.
  - A player may update only their own `selfRating`. Only the organizer may set `organizerOverride`.
  - A player may delete their own document; the organizer may delete any member.
- **sessions:** members read. Only the organizer creates, edits or cancels. A change to `teamsPublished` is valid only from `scheduled`.
- **checkins:** a player writes only their own document. They must be a member, the session must be `scheduled`, and `request.time` must be within `[checkInOpensAt, checkInClosesAt]`. The organizer may delete any check-in.

**Known limitation.** Rules cannot verify GPS. A rooted device could fake a location. Mitigations: the mock-location check, the organizer's ability to remove check-ins, and check-ins being visible to the group. This is an accepted trade-off for a friendly group.

## 9. Screens

- **Sign-in:** Google button.
- **My groups:** list, create group, join by code.
- **Group detail:** upcoming sessions and members with ratings. Organizer only: group settings (court location via "use my current location", radius, default team size), schedule editor, rating overrides.
- **Session detail:** check-in / check-out button that shows why it is blocked, plus a live list of checked-in players. Organizer only: Generate, Reshuffle, Publish, Cancel session.
- **Teams:** shown after publishing, with the player's own team highlighted.

## 10. Error handling

`Failure` types: `NotInGeofence`, `MockLocationDetected`, `LocationPermissionDenied`, `CheckInClosed`, `SessionAlreadyPublished`, `InvalidInviteCode`, `NotEnoughPlayers`, `Unauthorized` (Rules rejection), `Offline`. Repositories translate Firebase and location exceptions into these; the UI maps each to a message.

Check-in, publish and join use Firestore transactions, which fail offline instead of queueing, so a queued write cannot land after the window closes. Read screens work from Firestore's local cache and show an offline banner.

## 11. Testing

Test-first, layer by layer.

- **Domain unit tests:** `TeamBalancer` (worked examples and randomized property tests over many rosters and seeds), schedule expansion (weekday selection, end date, a DST boundary, idempotent ids), Haversine distance, and every use case against fake repositories.
- **Data tests:** DTO/entity mappers, and repositories against a Firestore fake.
- **Security Rules tests:** against the Firebase Emulator, covering allowed and denied writes (for example, checking in as another user, or a player editing `organizerOverride`).
- **Widget tests:** check-in states and the generate/reshuffle/publish flow, using Riverpod overrides.
- **Manual checklist:** geofence behavior on real devices, inside and outside the radius.

## 12. Out of scope for v1

- Late arrivals after teams are published.
- More than one organizer per group, and organizer transfer.
- Push notifications.
- Match scores and stats.
- Recurrence beyond weekly weekdays.
- Cloud Functions.
- Web and desktop targets.

## 13. Prerequisites (owner action)

Create the Firebase project, enable Google sign-in, register the Android and iOS apps (Android needs the SHA-1 fingerprint), and run `flutterfire configure`. The implementation plan will list the exact steps.
