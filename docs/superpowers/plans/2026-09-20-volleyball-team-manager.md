# Volleyball Team Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter (Android + iOS) app where players check in at the court and an organizer generates balanced volleyball teams, using Google sign-in and Firebase, built with Clean Architecture.

**Architecture:** Feature-first Clean Architecture (`auth`, `groups`, `sessions`, `teams`), each with `domain` (pure Dart), `data` (Firestore / Firebase Auth / geolocator) and `presentation` (Riverpod + screens). The dependency rule `presentation -> domain <- data` is enforced by a test. The backend is Firebase Auth + Firestore + Security Rules only (no Cloud Functions), so team generation runs on the organizer's device and recurring games are created by the organizer's device.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `flutter_riverpod` (no code generation), `go_router`, `firebase_auth`, `google_sign_in`, `cloud_firestore`, `geolocator`, `timezone`, `equatable`; tests with `flutter_test`, `fake_cloud_firestore`, and the Firebase Emulator (`@firebase/rules-unit-testing`).

**Spec:** `docs/superpowers/specs/2026-09-20-volleyball-team-manager-design.md`

## How this plan was verified

Every code block in Tasks 1–19 was compiled and run in a scratch Flutter project (Flutter 3.44.2, Dart 3.12.2) before it was written here. That project passes **98 Flutter tests** (domain, data against `fake_cloud_firestore`, widget tests, architecture guard) with a clean `flutter analyze`, and the Security Rules pass **22 emulator tests** (Task 12).

**Not verified, because it needs a real Firebase project or a device:** Google sign-in, real Firestore behaviour, GPS. Those are covered by the manual steps in Tasks 11, 15 and 19.

## Global Constraints

These come from the spec; every task's requirements include them.

- Flutter (Dart 3), Android and iOS only. No web or desktop targets.
- Clean Architecture, feature-first. Dependency rule: `presentation -> domain <- data`.
- The domain layer is pure Dart: no Flutter or Firebase imports. `package:timezone` and `equatable` are allowed.
- State management and DI: `flutter_riverpod` **without code generation**. Navigation: `go_router`.
- Backend: Firebase Auth + Firestore + Security Rules. **No Cloud Functions.**
- Errors: use cases return `Result<T>`; exceptions never cross layer boundaries.
- Skill rating: integer 1 to 5. Effective rating = `organizerOverride ?? selfRating`.
- Team count: `max(2, round(n / teamSize))`. Fewer than 4 checked-in players fails with `NotEnoughPlayers`. Team sizes differ by at most 1. No team gets two players from the same tier. The swap pass compares team **average** ratings.
- Check-in window: opens 60 minutes before the start, closes 3 hours after it, and is closed once teams are published or the session is cancelled.
- Defaults: geofence radius 150 m, team size 6.
- Recurrence: weekly on chosen weekdays, wall-clock time in the group's IANA timezone, materialized 4 weeks ahead. Session ids are the local date-time, e.g. `2026-09-22T19:00`.
- Invite codes: 8 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`.
- Check-in, publish and join/create-group use Firestore transactions, so they fail offline instead of queueing.
- Test-first: write the failing test, see it fail, implement, see it pass, commit.

## Clarifications made while planning

The spec is approved; these are details it left open. Please skim them.

1. **`Team` lives in `features/sessions/domain/entities/`**, not `teams/`. `GameSession` stores its teams, so `Team` in `teams/` would create a cycle between the two features. Feature dependencies now run one way: `auth <- groups <- sessions <- teams`.
2. **One-off sessions are created with `modified: true`**, so changing the weekly schedule never deletes them.
3. **Three extra `Failure` types:** `NotFound`, `InvalidInput`, `SessionCancelled`.
4. **`EditSession` use case and an "Edit game" dialog** (team size and start time) implement the spec's "editing one occurrence".
5. **"My groups" needs a collection-group query.** That adds one Security Rule (`match /{path=**}/members/{userId}`, restricted to your own documents) and a collection-group field override in `firestore.indexes.json`. The spec's rules section did not list them.
6. **Creating a group uses a transaction** (like join, check-in and publish) so it fails offline instead of hanging.
7. **The timezone lives only in `Schedule`.** The device's timezone is captured the first time a schedule is saved.
8. **Dependency pins**, each checked against Flutter 3.44.2:
   - `flutter_riverpod ^2.6.1`: keeps the no-codegen API stable.
   - `go_router ^17.0.0`: version 18 depends on a `material_ui` package that does not compile on 3.44.2.
   - `equatable ^2.0.7`: `fake_cloud_firestore` needs 2.x.
   - `google_sign_in ^7.0.0`: the plan uses its `authenticate()` API.
   - `flutter_timezone ^4.1.0`: `getLocalTimezone()` returns a `String` (version 5 returns a `TimezoneInfo`).
9. **Android Google sign-in needs the Firebase "Web client ID"** passed as `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` (Task 11).
10. **Not included: the offline banner** from spec section 10. Actions that need the network (check-in, publish, join, create group) fail with a clear "You seem to be offline" message, and read screens keep working from Firestore's local cache, but no persistent banner is shown. Adding one needs a connectivity signal (for example Firestore snapshot metadata); it is a small follow-up if you want it.

## File structure

```
pubspec.yaml, analysis_options.yaml
firebase.json, firestore.rules, firestore.indexes.json      Firebase config (Tasks 11-12)
rules-tests/                                                Security Rules tests (Node, emulator)
lib/
  main.dart, firebase_config.dart, firebase_options.dart(generated)
  app/            app.dart, router.dart, composition_root.dart
  core/           failure, result, geo, random_codes, location_provider, providers,
                  failure_message, format, data/ (firestore_guard, geolocator), widgets/
  features/
    auth/         domain: AppUser, AuthRepository, sign-in/out/watch use cases
                  data: FirebaseAuthRepository; presentation: providers, SignInScreen
    groups/       domain: Group, Member, Schedule, GroupRepository, OrganizerGuard, use cases
                  data: mappers + FirestoreGroupRepository
                  presentation: providers, groups/detail/settings/schedule screens, widgets
    sessions/     domain: GameSession, CheckIn, Team, SessionRepository, ScheduleExpander, use cases
                  data: mappers + FirestoreSessionRepository
                  presentation: providers, SessionScreen
    teams/        domain: TeamBalancer, GenerateTeams, PublishTeams
                  presentation: providers, TeamsView
test/             mirrors lib/, plus support/ (in-memory fakes, app harness) and architecture_test.dart
```

Run every command from the project root. If `flutter create` leaves a default `test/widget_test.dart`, delete it: the default counter test does not apply.

---

## Phase 0: Foundation

### Task 1: Project scaffold, dependencies and the architecture guard

**Files:**
- Create: the Flutter project skeleton (generated), `analysis_options.yaml`
- Modify: `pubspec.yaml` (via `flutter pub add`)
- Test: `test/architecture_test.dart`

**Interfaces:**
- Produces: package name `volley_teams` (imports look like `package:volley_teams/...`); a test that fails whenever a layer imports something it must not.

- [ ] **Step 1: Check the target folder, then create the project**

Run `ls -A` first. If the folder already holds a Flutter project, stop and decide with the owner whether to use a subfolder instead. In an empty (or docs-only) folder:

```bash
flutter create --project-name volley_teams --org com.example --platforms android,ios --empty .
git init   # skip if the folder is already a git repository
```

- [ ] **Step 2: Add dependencies**

The pins are deliberate (see "Clarifications", item 8).

```bash
flutter pub add flutter_riverpod:^2.6.1 go_router:^17.0.0 equatable:^2.0.7 timezone \
  firebase_core firebase_auth cloud_firestore google_sign_in:^7.0.0 geolocator flutter_timezone:^4.1.0
flutter pub add --dev fake_cloud_firestore
```

Expected: both commands end with `Changed N dependencies!` and no version-solving error.

- [ ] **Step 3: Configure the analyzer**

Replace `analysis_options.yaml`. The excludes keep build output and the generated Firebase options file out of analysis.

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - build/**
    - lib/firebase_options.dart
```

- [ ] **Step 4: Write the architecture guard test**

`test/architecture_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the dependency rule: presentation -> domain <- data.
void main() {
  const forbiddenInDomain = [
    'package:flutter/',
    'package:flutter_riverpod/',
    'package:go_router/',
    'package:firebase_core/',
    'package:firebase_auth/',
    'package:cloud_firestore/',
    'package:google_sign_in/',
    'package:geolocator/',
    'package:flutter_timezone/',
    'dart:ui',
    '/data/',
    '/presentation/',
  ];

  List<File> dartFiles(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  List<String> imports(File file) => file
      .readAsLinesSync()
      .where((line) => line.startsWith('import ') || line.startsWith('export '))
      .toList();

  List<String> violations(Iterable<File> files, List<String> forbidden) => [
        for (final file in files)
          for (final line in imports(file))
            if (forbidden.any(line.contains)) '${file.path}: $line',
      ];

  test('domain code imports no framework, data or presentation code', () {
    final domain = [
      ...dartFiles('lib/features').where((f) => f.path.contains('/domain/')),
      for (final name in ['failure', 'result', 'geo', 'random_codes', 'location_provider'])
        File('lib/core/$name.dart'),
    ].where((f) => f.existsSync());
    expect(violations(domain, forbiddenInDomain), isEmpty);
  });

  test('data code never imports presentation code', () {
    final data = dartFiles('lib/features').where((f) => f.path.contains('/data/'));
    expect(violations(data, ['/presentation/']), isEmpty);
  });

  test('presentation code never imports data code', () {
    final presentation = dartFiles('lib/features').where((f) => f.path.contains('/presentation/'));
    expect(violations(presentation, ['/data/']), isEmpty);
  });
}
```

- [ ] **Step 5: Run it, then prove it can fail**

```bash
flutter test test/architecture_test.dart
```

Expected: PASS (there is no source yet, so nothing can violate the rule). Now add a deliberate violation and confirm the guard catches it:

```bash
mkdir -p lib/features/demo/domain
echo "import 'package:flutter/material.dart';" > lib/features/demo/domain/bad.dart
flutter test test/architecture_test.dart
```

Expected: FAIL, naming `lib/features/demo/domain/bad.dart`. Remove it:

```bash
rm -rf lib/features/demo
flutter test test/architecture_test.dart   # PASS again
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold Flutter project with dependency-rule guard test"
```

---

## Phase 1: Domain layer (pure Dart)

Tasks 2 to 10 build `lib/core` and every `domain` folder. Nothing here imports Flutter or Firebase, and the architecture guard keeps it that way.

### Task 2: Core types (Failure, Result, geo, random codes, location port)

**Files:**
- Create: `lib/core/failure.dart`, `lib/core/result.dart`, `lib/core/geo.dart`, `lib/core/random_codes.dart`, `lib/core/location_provider.dart`
- Test: `test/core/result_test.dart`, `test/core/geo_test.dart`, `test/core/random_codes_test.dart`

**Interfaces:**
- Produces: `Result<T>` with `Ok(data)` / `Err(error)`, getters `isOk`, `isErr`, `value`, `failure`, `castErr<R>()`, `fold`; the sealed `Failure` family; `Coordinates(lat, lng)` and `distanceMeters(a, b)`; `RandomCodes(Random)` with `id([length])` and `inviteCode()`; `LocationProvider.currentPosition() -> Future<Result<DevicePosition>>`.

- [ ] **Step 1: Write the failing tests**

`test/core/result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/result.dart';

void main() {
  test('Ok exposes its value', () {
    const Result<int> r = Ok(3);
    expect(r.isOk, isTrue);
    expect(r.value, 3);
  });

  test('Err exposes its failure and can be re-wrapped', () {
    const Result<int> r = Err(CheckInClosed());
    expect(r.isErr, isTrue);
    expect(r.failure, isA<CheckInClosed>());
    final Result<String> other = r.castErr();
    expect(other.failure, isA<CheckInClosed>());
  });

  test('fold picks the right branch', () {
    const Result<int> ok = Ok(2);
    const Result<int> err = Err(Offline());
    expect(ok.fold((v) => 'ok $v', (f) => 'err'), 'ok 2');
    expect(err.fold((v) => 'ok', (f) => 'err ${f.runtimeType}'), 'err Offline');
  });
}
```

`test/core/geo_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';

void main() {
  test('distance between identical points is zero', () {
    const p = Coordinates(-23.55, -46.63);
    expect(distanceMeters(p, p), 0);
  });

  test('one degree of longitude at the equator is about 111.2 km', () {
    expect(
      distanceMeters(const Coordinates(0, 0), const Coordinates(0, 1)),
      closeTo(111195, 10),
    );
  });

  test('a 100 m offset north is measured as about 100 m', () {
    // 100 m of latitude is 100 / 111195 degrees.
    final d = distanceMeters(
      const Coordinates(40, -74),
      const Coordinates(40 + 100 / 111195, -74),
    );
    expect(d, closeTo(100, 0.5));
  });
}
```

`test/core/random_codes_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/random_codes.dart';

void main() {
  test('invite codes are 8 characters from the unambiguous alphabet', () {
    final codes = RandomCodes(Random(1));
    for (var i = 0; i < 50; i++) {
      final code = codes.inviteCode();
      expect(code, hasLength(RandomCodes.inviteLength));
      expect(code.split('').every(RandomCodes.inviteAlphabet.contains), isTrue);
    }
  });

  test('ids have the requested length and differ between calls', () {
    final codes = RandomCodes(Random(1));
    expect(codes.id(), hasLength(20));
    expect(codes.id(12), hasLength(12));
    expect(codes.id(), isNot(codes.id()));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
flutter test test/core
```

Expected: FAIL to compile: `Target of URI doesn't exist` for `package:volley_teams/core/...`.

- [ ] **Step 3: Implement**

`lib/core/failure.dart`:

```dart
/// Every expected way an operation can fail. Use cases return these inside a
/// `Result`; exceptions never cross layer boundaries.
sealed class Failure {
  const Failure([this.message]);

  final String? message;

  @override
  String toString() => message == null ? '$runtimeType' : '$runtimeType: $message';
}

final class NotInGeofence extends Failure {
  const NotInGeofence({required this.distanceMeters, required this.radiusMeters});

  final double distanceMeters;
  final double radiusMeters;
}

final class MockLocationDetected extends Failure {
  const MockLocationDetected();
}

final class LocationPermissionDenied extends Failure {
  const LocationPermissionDenied();
}

final class CheckInClosed extends Failure {
  const CheckInClosed();
}

final class SessionAlreadyPublished extends Failure {
  const SessionAlreadyPublished();
}

final class SessionCancelled extends Failure {
  const SessionCancelled();
}

final class InvalidInviteCode extends Failure {
  const InvalidInviteCode();
}

final class NotEnoughPlayers extends Failure {
  const NotEnoughPlayers({required this.have, required this.need});

  final int have;
  final int need;
}

final class Unauthorized extends Failure {
  const Unauthorized([super.message]);
}

final class Offline extends Failure {
  const Offline();
}

final class NotFound extends Failure {
  const NotFound(String super.message);
}

final class InvalidInput extends Failure {
  const InvalidInput(String super.message);
}

final class Unexpected extends Failure {
  const Unexpected(String super.message);
}
```

`lib/core/result.dart`:

```dart
import 'failure.dart';

/// Success value or [Failure]. Use cases and repositories return this instead
/// of throwing.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The success value. Only call after checking [isOk].
  T get value => (this as Ok<T>).data;

  /// The failure. Only call after checking [isErr].
  Failure get failure => (this as Err<T>).error;

  /// Re-wraps this failure for a different success type (early-return helper).
  Err<R> castErr<R>() => Err<R>(failure);

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final data) => onOk(data),
        Err<T>(:final error) => onErr(error),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.data);

  final T data;
}

final class Err<T> extends Result<T> {
  const Err(this.error);

  final Failure error;
}
```

`lib/core/geo.dart`:

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';

class Coordinates extends Equatable {
  const Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  List<Object?> get props => [latitude, longitude];
}

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two points (Haversine formula).
double distanceMeters(Coordinates a, Coordinates b) {
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final dLat = lat2 - lat1;
  final dLng = _radians(b.longitude - a.longitude);
  final h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * asin(min(1.0, sqrt(h)));
}

double _radians(double degrees) => degrees * pi / 180;
```

`lib/core/random_codes.dart`:

```dart
import 'dart:math';

/// Generates document ids and invite codes from an injected [Random].
class RandomCodes {
  RandomCodes(this._random);

  /// 32 characters, no `I`, `O`, `0` or `1`, so codes are easy to read aloud.
  static const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const inviteLength = 8;
  static const _idAlphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final Random _random;

  String id([int length = 20]) => _pick(_idAlphabet, length);

  String inviteCode() => _pick(inviteAlphabet, inviteLength);

  String _pick(String alphabet, int length) => String.fromCharCodes(
        List.generate(
          length,
          (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
        ),
      );
}
```

`lib/core/location_provider.dart`:

```dart
import 'package:equatable/equatable.dart';

import 'geo.dart';
import 'result.dart';

class DevicePosition extends Equatable {
  const DevicePosition({required this.coordinates, this.isMocked = false});

  final Coordinates coordinates;

  /// True when the platform reports the fix as coming from a mock provider.
  final bool isMocked;

  @override
  List<Object?> get props => [coordinates, isMocked];
}

/// Reads the device position. Implemented in the data layer with `geolocator`.
abstract interface class LocationProvider {
  /// Fails with `LocationPermissionDenied` when permission is refused, or
  /// `Unexpected` when location services are off or no fix is available.
  Future<Result<DevicePosition>> currentPosition();
}
```

- [ ] **Step 4: Run tests and the analyzer**

```bash
flutter test test/core test/architecture_test.dart && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(core): add Result, Failure, geo distance, random codes and location port"
```

### Task 3: Domain entities

**Files:**
- Create: `lib/features/groups/domain/entities/{member,schedule,group}.dart`, `lib/features/sessions/domain/entities/{team,check_in,game_session}.dart`
- Test: `test/features/groups/member_test.dart`, `test/features/sessions/game_session_test.dart`

**Interfaces:**
- Consumes: `Coordinates` (Task 2).
- Produces:
  - `Member(userId, displayName, photoUrl?, selfRating, organizerOverride?, role)` with `effectiveRating`, `copyWith(selfRating:, organizerOverride: () => x)`; `isValidRating(int)`, `minRating`, `maxRating`; `MemberRole {organizer, player}`.
  - `Schedule(weekdays, startTime: LocalTime, endDate?, timezone)`.
  - `Group(id, name, organizerId, inviteCode, court, radiusMeters=150, defaultTeamSize=6, schedule?)` with `copyWith(..., schedule: () => x)`.
  - `Team(index, playerIds, ratingTotal)` with `averageRating`.
  - `CheckIn(userId, checkedInAt, distanceMeters)`.
  - `GameSession` with `GameSession.scheduled(...)`, `isCheckInOpen(now)`, `copyWith(startsAt:, teamSize:, status:, modified:, teams:)`, and `SessionStatus {scheduled, teamsPublished, cancelled}`. `GameSession.checkInOpensBefore` is 60 minutes and `checkInClosesAfter` is 3 hours.

- [ ] **Step 1: Write the failing tests**

`test/features/groups/member_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';

void main() {
  const member = Member(
    userId: 'u1',
    displayName: 'Ana',
    selfRating: 4,
    role: MemberRole.player,
  );

  test('effective rating is the self rating when there is no override', () {
    expect(member.effectiveRating, 4);
  });

  test('effective rating prefers the organizer override', () {
    expect(member.copyWith(organizerOverride: () => 2).effectiveRating, 2);
  });

  test('an override can be cleared again', () {
    final overridden = member.copyWith(organizerOverride: () => 2);
    expect(overridden.copyWith(organizerOverride: () => null).effectiveRating, 4);
  });

  test('ratings must be between 1 and 5', () {
    expect([0, 1, 5, 6].map(isValidRating), [false, true, true, false]);
  });
}
```

`test/features/sessions/game_session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';

void main() {
  final start = DateTime.utc(2026, 9, 22, 22);
  final session = GameSession.scheduled(
    id: '2026-09-22T19:00',
    startsAt: start,
    teamSize: 6,
    court: const Coordinates(0, 0),
    radiusMeters: 150,
  );

  test('check-in window is 60 minutes before to 3 hours after the start', () {
    expect(session.checkInOpensAt, DateTime.utc(2026, 9, 22, 21));
    expect(session.checkInClosesAt, DateTime.utc(2026, 9, 23, 1));
  });

  test('check-in is open only inside the window', () {
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 22, 20, 59)), isFalse);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 22, 21)), isTrue);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 23, 1)), isTrue);
    expect(session.isCheckInOpen(DateTime.utc(2026, 9, 23, 1, 1)), isFalse);
  });

  test('check-in is closed once published or cancelled', () {
    final inside = DateTime.utc(2026, 9, 22, 22);
    expect(
      session.copyWith(status: SessionStatus.teamsPublished).isCheckInOpen(inside),
      isFalse,
    );
    expect(
      session.copyWith(status: SessionStatus.cancelled).isCheckInOpen(inside),
      isFalse,
    );
  });

  test('moving the start moves the window', () {
    final moved = session.copyWith(startsAt: DateTime.utc(2026, 9, 22, 23));
    expect(moved.checkInOpensAt, DateTime.utc(2026, 9, 22, 22));
  });

  test('team average is total divided by size', () {
    const team = Team(index: 0, playerIds: ['a', 'b', 'c'], ratingTotal: 10);
    expect(team.averageRating, closeTo(3.333, 0.001));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
flutter test test/features/groups/member_test.dart test/features/sessions/game_session_test.dart
```

Expected: FAIL to compile (missing entity files).

- [ ] **Step 3: Implement**

`lib/features/groups/domain/entities/member.dart`:

```dart
import 'package:equatable/equatable.dart';

const minRating = 1;
const maxRating = 5;

bool isValidRating(int rating) => rating >= minRating && rating <= maxRating;

enum MemberRole { organizer, player }

class Member extends Equatable {
  const Member({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.selfRating,
    this.organizerOverride,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final int selfRating;
  final int? organizerOverride;
  final MemberRole role;

  /// The rating the team balancer uses.
  int get effectiveRating => organizerOverride ?? selfRating;

  bool get isOrganizer => role == MemberRole.organizer;

  Member copyWith({int? selfRating, int? Function()? organizerOverride}) => Member(
        userId: userId,
        displayName: displayName,
        photoUrl: photoUrl,
        selfRating: selfRating ?? this.selfRating,
        organizerOverride:
            organizerOverride != null ? organizerOverride() : this.organizerOverride,
        role: role,
      );

  @override
  List<Object?> get props =>
      [userId, displayName, photoUrl, selfRating, organizerOverride, role];
}
```

`lib/features/groups/domain/entities/schedule.dart`:

```dart
import 'package:equatable/equatable.dart';

class LocalTime extends Equatable {
  const LocalTime(this.hour, this.minute);

  final int hour;
  final int minute;

  @override
  List<Object?> get props => [hour, minute];
}

/// Weekly recurrence rule, expressed as wall-clock time in [timezone] so that
/// daylight-saving changes never shift a game by an hour.
class Schedule extends Equatable {
  const Schedule({
    required this.weekdays,
    required this.startTime,
    this.endDate,
    required this.timezone,
  });

  /// `DateTime.monday` (1) through `DateTime.sunday` (7).
  final Set<int> weekdays;
  final LocalTime startTime;

  /// Last local calendar day (inclusive) on which a game may occur. Only the
  /// year, month and day are used.
  final DateTime? endDate;

  /// IANA name, e.g. `America/New_York`.
  final String timezone;

  @override
  List<Object?> get props => [weekdays, startTime, endDate, timezone];
}
```

`lib/features/groups/domain/entities/group.dart`:

```dart
import 'package:equatable/equatable.dart';

import '../../../../core/geo.dart';
import 'schedule.dart';

class Group extends Equatable {
  const Group({
    required this.id,
    required this.name,
    required this.organizerId,
    required this.inviteCode,
    required this.court,
    this.radiusMeters = standardRadiusMeters,
    this.defaultTeamSize = standardTeamSize,
    this.schedule,
  });

  static const standardRadiusMeters = 150.0;
  static const standardTeamSize = 6;

  final String id;
  final String name;
  final String organizerId;
  final String inviteCode;
  final Coordinates court;
  final double radiusMeters;
  final int defaultTeamSize;
  final Schedule? schedule;

  Group copyWith({
    Coordinates? court,
    double? radiusMeters,
    int? defaultTeamSize,
    Schedule? Function()? schedule,
  }) =>
      Group(
        id: id,
        name: name,
        organizerId: organizerId,
        inviteCode: inviteCode,
        court: court ?? this.court,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        defaultTeamSize: defaultTeamSize ?? this.defaultTeamSize,
        schedule: schedule != null ? schedule() : this.schedule,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        organizerId,
        inviteCode,
        court,
        radiusMeters,
        defaultTeamSize,
        schedule,
      ];
}
```

`lib/features/sessions/domain/entities/team.dart`:

```dart
import 'package:equatable/equatable.dart';

class Team extends Equatable {
  const Team({
    required this.index,
    required this.playerIds,
    required this.ratingTotal,
  });

  final int index;
  final List<String> playerIds;
  final int ratingTotal;

  double get averageRating =>
      playerIds.isEmpty ? 0 : ratingTotal / playerIds.length;

  @override
  List<Object?> get props => [index, playerIds, ratingTotal];
}
```

`lib/features/sessions/domain/entities/check_in.dart`:

```dart
import 'package:equatable/equatable.dart';

class CheckIn extends Equatable {
  const CheckIn({
    required this.userId,
    required this.checkedInAt,
    required this.distanceMeters,
  });

  final String userId;
  final DateTime checkedInAt;
  final double distanceMeters;

  @override
  List<Object?> get props => [userId, checkedInAt, distanceMeters];
}
```

`lib/features/sessions/domain/entities/game_session.dart`:

```dart
import 'package:equatable/equatable.dart';

import '../../../../core/geo.dart';
import 'team.dart';

enum SessionStatus { scheduled, teamsPublished, cancelled }

class GameSession extends Equatable {
  const GameSession({
    required this.id,
    required this.startsAt,
    required this.teamSize,
    required this.court,
    required this.radiusMeters,
    required this.checkInOpensAt,
    required this.checkInClosesAt,
    required this.status,
    required this.modified,
    required this.teams,
  });

  /// A new, unmodified `scheduled` session. [startsAt] must be UTC.
  factory GameSession.scheduled({
    required String id,
    required DateTime startsAt,
    required int teamSize,
    required Coordinates court,
    required double radiusMeters,
    bool modified = false,
  }) {
    assert(startsAt.isUtc, 'startsAt must be UTC');
    return GameSession(
      id: id,
      startsAt: startsAt,
      teamSize: teamSize,
      court: court,
      radiusMeters: radiusMeters,
      checkInOpensAt: startsAt.subtract(checkInOpensBefore),
      checkInClosesAt: startsAt.add(checkInClosesAfter),
      status: SessionStatus.scheduled,
      modified: modified,
      teams: const [],
    );
  }

  static const checkInOpensBefore = Duration(minutes: 60);
  static const checkInClosesAfter = Duration(hours: 3);

  final String id;
  final DateTime startsAt;
  final int teamSize;
  final Coordinates court;
  final double radiusMeters;
  final DateTime checkInOpensAt;
  final DateTime checkInClosesAt;
  final SessionStatus status;

  /// True once the organizer edited or cancelled this occurrence, and for
  /// one-off sessions: the recurring schedule must not touch it.
  final bool modified;
  final List<Team> teams;

  bool isCheckInOpen(DateTime now) =>
      status == SessionStatus.scheduled &&
      !now.isBefore(checkInOpensAt) &&
      !now.isAfter(checkInClosesAt);

  GameSession copyWith({
    DateTime? startsAt,
    int? teamSize,
    SessionStatus? status,
    bool? modified,
    List<Team>? teams,
  }) {
    final start = startsAt ?? this.startsAt;
    return GameSession(
      id: id,
      startsAt: start,
      teamSize: teamSize ?? this.teamSize,
      court: court,
      radiusMeters: radiusMeters,
      checkInOpensAt: start.subtract(checkInOpensBefore),
      checkInClosesAt: start.add(checkInClosesAfter),
      status: status ?? this.status,
      modified: modified ?? this.modified,
      teams: teams ?? this.teams,
    );
  }

  @override
  List<Object?> get props => [
        id,
        startsAt,
        teamSize,
        court,
        radiusMeters,
        checkInOpensAt,
        checkInClosesAt,
        status,
        modified,
        teams,
      ];
}
```

- [ ] **Step 4: Run tests**

```bash
flutter test test/features/groups/member_test.dart test/features/sessions/game_session_test.dart test/architecture_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(domain): add Group, Member, Schedule, GameSession, CheckIn and Team entities"
```

### Task 4: TeamBalancer

**Files:**
- Create: `lib/features/teams/domain/services/team_balancer.dart`
- Test: `test/features/teams/team_balancer_test.dart`

**Interfaces:**
- Consumes: `Team` (Task 3), `Result`, `NotEnoughPlayers` (Task 2).
- Produces: `RatedPlayer(id, rating)`; `TeamBalancer({swapPass = true})` with `static int teamCountFor(int playerCount, int teamSize)`, `static const minPlayers = 4`, and `Result<List<Team>> balance({required List<RatedPlayer> players, required int teamSize, required Random random})`.

The tests include a randomized property test over 400 rosters. The "one player per tier" check is written to be robust to rating ties: within a team, the j-th best rating must lie between the lowest and highest rating of tier j.

- [ ] **Step 1: Write the failing tests**

`test/features/teams/team_balancer_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';
import 'package:volley_teams/features/teams/domain/services/team_balancer.dart';

List<RatedPlayer> roster(List<int> ratings) => [
      for (var i = 0; i < ratings.length; i++)
        RatedPlayer(id: 'p$i', rating: ratings[i]),
    ];

double spreadOf(List<Team> teams) {
  final averages = teams.map((t) => t.averageRating);
  return averages.reduce(max) - averages.reduce(min);
}

/// Tie-robust check of "one player per tier on every team".
///
/// Tier j is `sorted[j*T .. j*T+T-1]` (ratings, highest first). If every team
/// has exactly one player per tier, then the j-th best rating of any team must
/// lie between the lowest and highest rating of tier j.
void expectOnePerTier(List<Team> teams, List<RatedPlayer> players) {
  final t = teams.length;
  final ratingOf = {for (final p in players) p.id: p.rating};
  final sorted = ratingOf.values.toList()..sort((a, b) => b.compareTo(a));
  for (final team in teams) {
    final ratings = [for (final id in team.playerIds) ratingOf[id]!]
      ..sort((a, b) => b.compareTo(a));
    for (var j = 0; j < ratings.length; j++) {
      final high = sorted[j * t];
      final low = sorted[min(j * t + t - 1, sorted.length - 1)];
      expect(
        ratings[j],
        inInclusiveRange(low, high),
        reason: 'team ${team.index} rank $j: $ratings vs tier [$low..$high]',
      );
    }
  }
}

void main() {
  const balancer = TeamBalancer();

  group('team count', () {
    test('rounds to the nearest whole team, minimum two', () {
      expect(TeamBalancer.teamCountFor(12, 6), 2);
      expect(TeamBalancer.teamCountFor(13, 6), 2);
      expect(TeamBalancer.teamCountFor(15, 6), 3); // 2.5 rounds up
      expect(TeamBalancer.teamCountFor(17, 6), 3);
      expect(TeamBalancer.teamCountFor(4, 6), 2); // never fewer than two
    });

    test('fewer than four players is rejected', () {
      final result = balancer.balance(
        players: roster([5, 4, 3]),
        teamSize: 6,
        random: Random(1),
      );
      expect(result.failure, isA<NotEnoughPlayers>());
    });

    test('team sizes: 13 -> 7+6, 17 -> 6+6+5, 15 -> 5+5+5', () {
      List<int> sizes(int n) {
        final teams = balancer
            .balance(
              players: roster(List.filled(n, 3)),
              teamSize: 6,
              random: Random(7),
            )
            .value;
        return teams.map((t) => t.playerIds.length).toList()..sort((a, b) => b.compareTo(a));
      }

      expect(sizes(13), [7, 6]);
      expect(sizes(17), [6, 6, 5]);
      expect(sizes(15), [5, 5, 5]);
    });
  });

  group('balancing', () {
    test('two teams of four each get one player of every rating', () {
      final teams = balancer
          .balance(
            players: roster([5, 5, 4, 4, 3, 3, 2, 2]),
            teamSize: 4,
            random: Random(3),
          )
          .value;
      for (final team in teams) {
        final ratings = team.playerIds
            .map((id) => [5, 5, 4, 4, 3, 3, 2, 2][int.parse(id.substring(1))])
            .toList()
          ..sort((a, b) => b.compareTo(a));
        expect(ratings, [5, 4, 3, 2]);
        expect(team.ratingTotal, 14);
      }
    });

    test('the three best players of a 3-team game are on different teams', () {
      final players = roster([5, 5, 5, 3, 3, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1]);
      for (var seed = 0; seed < 20; seed++) {
        final teams = balancer.balance(players: players, teamSize: 6, random: Random(seed)).value;
        expect(teams, hasLength(3));
        for (final team in teams) {
          final aces = team.playerIds.where((id) => players.firstWhere((p) => p.id == id).rating == 5);
          expect(aces, hasLength(1), reason: 'seed $seed team ${team.index}');
        }
      }
    });

    test('the same seed gives the same teams', () {
      final players = roster([5, 4, 4, 3, 3, 3, 2, 2, 1, 5, 4, 2, 3]);
      final a = balancer.balance(players: players, teamSize: 6, random: Random(99)).value;
      final b = balancer.balance(players: players, teamSize: 6, random: Random(99)).value;
      expect(a, b);
    });

    test('different seeds vary the teams', () {
      final players = roster(List.generate(12, (i) => 1 + i % 5));
      final draws = {
        for (var seed = 0; seed < 10; seed++)
          balancer
              .balance(players: players, teamSize: 6, random: Random(seed))
              .value
              .map((t) => t.playerIds.toSet())
              .toString(),
      };
      expect(draws.length, greaterThan(1));
    });
  });

  group('properties over random rosters', () {
    test('hold for 400 rosters', () {
      final meta = Random(2026);
      for (var run = 0; run < 400; run++) {
        final n = 4 + meta.nextInt(37); // 4..40 players
        final teamSize = 2 + meta.nextInt(7); // 2..8
        final players = roster([for (var i = 0; i < n; i++) 1 + meta.nextInt(5)]);
        final seed = meta.nextInt(1 << 30);
        final label = 'run $run n=$n teamSize=$teamSize seed=$seed';

        final teams = balancer.balance(players: players, teamSize: teamSize, random: Random(seed)).value;

        // Everyone assigned exactly once.
        final assigned = teams.expand((t) => t.playerIds).toList()..sort();
        expect(assigned, ([for (final p in players) p.id]..sort()), reason: label);

        // Team count and sizes.
        expect(teams, hasLength(TeamBalancer.teamCountFor(n, teamSize)), reason: label);
        final sizes = teams.map((t) => t.playerIds.length);
        expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1), reason: label);

        // Totals are consistent.
        final ratingOf = {for (final p in players) p.id: p.rating};
        for (final team in teams) {
          expect(team.ratingTotal, team.playerIds.fold<int>(0, (s, id) => s + ratingOf[id]!), reason: label);
        }

        // One player per tier on every team.
        expectOnePerTier(teams, players);

        // The swap pass never makes the spread worse.
        final raw = const TeamBalancer(swapPass: false)
            .balance(players: players, teamSize: teamSize, random: Random(seed))
            .value;
        expect(spreadOf(teams), lessThanOrEqualTo(spreadOf(raw) + 1e-9), reason: label);
      }
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/teams/team_balancer_test.dart
```

Expected: FAIL to compile (`team_balancer.dart` missing).

- [ ] **Step 3: Implement**

`lib/features/teams/domain/services/team_balancer.dart`:

```dart
import 'dart:math';

import 'package:equatable/equatable.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../sessions/domain/entities/team.dart';

class RatedPlayer extends Equatable {
  const RatedPlayer({required this.id, required this.rating});

  final String id;
  final int rating;

  @override
  List<Object?> get props => [id, rating];
}

/// Splits players into balanced teams.
///
/// Players are ranked and cut into tiers of one player per team. Each tier is
/// dealt to the teams in random order, so no team gets two players from the
/// same tier (the strongest players never share a team). A swap pass then
/// narrows the gap between team average ratings, swapping only players of the
/// same tier so that guarantee is preserved.
class TeamBalancer {
  const TeamBalancer({this.swapPass = true});

  static const minPlayers = 4;
  static const _maxSwapIterations = 200;
  static const _epsilon = 1e-9;

  /// Disable only in tests, to compare against the raw draw.
  final bool swapPass;

  static int teamCountFor(int playerCount, int teamSize) =>
      max(2, (playerCount / teamSize).round());

  Result<List<Team>> balance({
    required List<RatedPlayer> players,
    required int teamSize,
    required Random random,
  }) {
    assert(teamSize >= 1);
    if (players.length < minPlayers) {
      return Err(NotEnoughPlayers(have: players.length, need: minPlayers));
    }
    final teamCount = teamCountFor(players.length, teamSize);
    final slots = _deal(_rank(players, random), teamCount, random);
    if (swapPass) _improve(slots);
    return Ok([
      for (var i = 0; i < teamCount; i++)
        Team(
          index: i,
          playerIds: [for (final slot in slots[i]) slot.player.id],
          ratingTotal: slots[i].fold(0, (sum, slot) => sum + slot.player.rating),
        ),
    ]);
  }

  /// Highest rating first; players with equal ratings are in random order.
  List<RatedPlayer> _rank(List<RatedPlayer> players, Random random) {
    final keyed = [
      for (final player in players) (player: player, tieBreak: random.nextDouble()),
    ]..sort((a, b) {
        final byRating = b.player.rating.compareTo(a.player.rating);
        return byRating != 0 ? byRating : a.tieBreak.compareTo(b.tieBreak);
      });
    return [for (final entry in keyed) entry.player];
  }

  List<List<_Slot>> _deal(List<RatedPlayer> ranked, int teamCount, Random random) {
    final teams = List.generate(teamCount, (_) => <_Slot>[]);
    for (var start = 0, tier = 0; start < ranked.length; start += teamCount, tier++) {
      final members = ranked.sublist(start, min(start + teamCount, ranked.length));
      // A shuffled team order gives each tier member a random distinct team;
      // a partial last tier therefore lands on random teams.
      final order = List<int>.generate(teamCount, (i) => i)..shuffle(random);
      for (var k = 0; k < members.length; k++) {
        teams[order[k]].add(_Slot(members[k], tier));
      }
    }
    return teams;
  }

  void _improve(List<List<_Slot>> teams) {
    final totals = [
      for (final team in teams) team.fold<int>(0, (sum, slot) => sum + slot.player.rating),
    ];
    final sizes = [for (final team in teams) team.length];

    for (var iteration = 0; iteration < _maxSwapIterations; iteration++) {
      var bestSpread = _spread(totals, sizes) - _epsilon;
      _Swap? best;
      for (var a = 0; a < teams.length; a++) {
        for (var b = a + 1; b < teams.length; b++) {
          for (var i = 0; i < teams[a].length; i++) {
            for (var j = 0; j < teams[b].length; j++) {
              final x = teams[a][i];
              final y = teams[b][j];
              if (x.tier != y.tier || x.player.rating == y.player.rating) continue;
              final delta = y.player.rating - x.player.rating;
              totals[a] += delta;
              totals[b] -= delta;
              final spread = _spread(totals, sizes);
              totals[a] -= delta;
              totals[b] += delta;
              if (spread < bestSpread) {
                bestSpread = spread;
                best = _Swap(a, i, b, j);
              }
            }
          }
        }
      }
      if (best == null) return;
      final x = teams[best.a][best.i];
      final y = teams[best.b][best.j];
      teams[best.a][best.i] = y;
      teams[best.b][best.j] = x;
      final delta = y.player.rating - x.player.rating;
      totals[best.a] += delta;
      totals[best.b] -= delta;
    }
  }

  double _spread(List<int> totals, List<int> sizes) {
    var lowest = double.infinity;
    var highest = double.negativeInfinity;
    for (var i = 0; i < totals.length; i++) {
      final average = totals[i] / sizes[i];
      lowest = min(lowest, average);
      highest = max(highest, average);
    }
    return highest - lowest;
  }
}

final class _Slot {
  const _Slot(this.player, this.tier);

  final RatedPlayer player;
  final int tier;
}

final class _Swap {
  const _Swap(this.a, this.i, this.b, this.j);

  final int a;
  final int i;
  final int b;
  final int j;
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/teams/team_balancer_test.dart
```

Expected: PASS.

- [ ] **Step 5: Mutation check: prove the property test can fail**

Temporarily allow cross-tier swaps by deleting `x.tier != y.tier ||` from the swap condition in `_improve`, then run the test again:

```bash
flutter test test/features/teams/team_balancer_test.dart
```

Expected: FAIL, with a message like `team 3 rank 1: [5, 5, 2, 2, 1, 1, 1] vs tier [3..4]`. Restore the line and re-run: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(teams): add tier-stratified TeamBalancer with swap pass"
```

### Task 5: ScheduleExpander (weekly recurrence with DST)

**Files:**
- Create: `lib/features/sessions/domain/services/schedule_expander.dart`
- Test: `test/features/sessions/schedule_expander_test.dart`

**Interfaces:**
- Consumes: `Schedule`, `LocalTime` (Task 3), `GameSession.checkInClosesAfter`.
- Produces: `SessionOccurrence(id, startsAt)` (UTC `startsAt`); `ScheduleExpander().expand({required Schedule schedule, required DateTime now, int horizonDays = 28})`. It needs `tz.initializeTimeZones()` to have run (tests do it in `setUpAll`; the app does it in `main`, Task 19).

- [ ] **Step 1: Write the failing tests**

`test/features/sessions/schedule_expander_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/sessions/domain/services/schedule_expander.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const expander = ScheduleExpander();

  const sundays = Schedule(
    weekdays: {DateTime.sunday},
    startTime: LocalTime(19, 0),
    timezone: 'America/New_York',
  );

  test('expands four weekly Sundays and keeps 19:00 local across the DST change', () {
    // 2026-03-01 is a Sunday; US daylight time starts on 2026-03-08.
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 1, 12));
    expect(result.map((o) => o.id), [
      '2026-03-01T19:00',
      '2026-03-08T19:00',
      '2026-03-15T19:00',
      '2026-03-22T19:00',
    ]);
    expect(result.map((o) => o.startsAt), [
      DateTime.utc(2026, 3, 2, 0), // 19:00 EST (UTC-5)
      DateTime.utc(2026, 3, 8, 23), // 19:00 EDT (UTC-4)
      DateTime.utc(2026, 3, 15, 23),
      DateTime.utc(2026, 3, 22, 23),
    ]);
    expect(result.every((o) => o.startsAt.isUtc), isTrue);
  });

  test('supports several weekdays', () {
    const tueThu = Schedule(
      weekdays: {DateTime.tuesday, DateTime.thursday},
      startTime: LocalTime(19, 30),
      timezone: 'America/New_York',
    );
    final result = expander.expand(schedule: tueThu, now: DateTime.utc(2026, 3, 1, 12));
    expect(result, hasLength(8));
    expect(result.first.id, '2026-03-03T19:30');
    expect(result.last.id, '2026-03-26T19:30');
  });

  test('stops at the end date (inclusive)', () {
    final ending = Schedule(
      weekdays: sundays.weekdays,
      startTime: sundays.startTime,
      timezone: sundays.timezone,
      endDate: DateTime(2026, 3, 8),
    );
    final result = expander.expand(schedule: ending, now: DateTime.utc(2026, 3, 1, 12));
    expect(result.map((o) => o.id), ['2026-03-01T19:00', '2026-03-08T19:00']);
  });

  test('skips a game whose check-in window has already closed', () {
    // 2026-03-02 12:00 UTC is after the Mar 1 game's window (closes 03:00 UTC).
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 2, 12));
    expect(result.first.id, '2026-03-08T19:00');
    expect(result, hasLength(4)); // Mar 8, 15, 22, 29
  });

  test('keeps a game that started but whose check-in is still open', () {
    // 2026-03-02 01:00 UTC = 20:00 EST on Mar 1: the 19:00 game is under way.
    final result = expander.expand(schedule: sundays, now: DateTime.utc(2026, 3, 2, 1));
    expect(result.first.id, '2026-03-01T19:00');
  });

  test('ids are stable when expanding twice', () {
    final now = DateTime.utc(2026, 3, 1, 12);
    expect(expander.expand(schedule: sundays, now: now),
        expander.expand(schedule: sundays, now: now));
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/sessions/schedule_expander_test.dart
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/features/sessions/domain/services/schedule_expander.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../groups/domain/entities/schedule.dart';
import '../entities/game_session.dart';

class SessionOccurrence extends Equatable {
  const SessionOccurrence({required this.id, required this.startsAt});

  /// Deterministic: the local date-time in the schedule's timezone,
  /// e.g. `2026-09-22T19:00`.
  final String id;

  /// UTC instant.
  final DateTime startsAt;

  @override
  List<Object?> get props => [id, startsAt];
}

/// Expands a weekly [Schedule] into concrete occurrences.
///
/// Requires `tz.initializeTimeZones()` to have run.
class ScheduleExpander {
  const ScheduleExpander();

  static const defaultHorizonDays = 28;

  /// Occurrences within [horizonDays] local days starting today. A game whose
  /// check-in window has already closed is skipped.
  List<SessionOccurrence> expand({
    required Schedule schedule,
    required DateTime now,
    int horizonDays = defaultHorizonDays,
  }) {
    final location = tz.getLocation(schedule.timezone);
    final localNow = tz.TZDateTime.from(now, location);
    // Plain UTC dates are used only for calendar arithmetic (no DST surprises).
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final end = schedule.endDate;
    final lastDay = end == null ? null : DateTime.utc(end.year, end.month, end.day);

    final occurrences = <SessionOccurrence>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final day = today.add(Duration(days: offset));
      if (lastDay != null && day.isAfter(lastDay)) break;
      if (!schedule.weekdays.contains(day.weekday)) continue;
      final start = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        schedule.startTime.hour,
        schedule.startTime.minute,
      );
      if (!start.add(GameSession.checkInClosesAfter).isAfter(now)) continue;
      occurrences.add(SessionOccurrence(
        id: _idFor(start),
        startsAt: DateTime.fromMillisecondsSinceEpoch(
          start.millisecondsSinceEpoch,
          isUtc: true,
        ),
      ));
    }
    return occurrences;
  }

  String _idFor(tz.TZDateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        'T${two(local.hour)}:${two(local.minute)}';
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/sessions/schedule_expander_test.dart
```

Expected: PASS. The first test proves 19:00 local stays 19:00 across the 2026-03-08 US daylight-saving change (UTC moves from 00:00 to 23:00).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(sessions): expand weekly schedules into DST-safe occurrences"
```

### Task 6: Groups domain (repository port, guard and use cases)

**Files:**
- Create: `lib/features/groups/domain/repositories/group_repository.dart`, `lib/features/groups/domain/usecases/{organizer_guard,create_group,join_group_by_code,update_self_rating,set_organizer_override,update_group_settings,watch_groups}.dart`
- Test: `test/support/changes.dart`, `test/support/fake_group_repository.dart`, `test/features/groups/group_use_cases_test.dart`

**Interfaces:**
- Consumes: `Group`, `Member`, `Coordinates`, `Result`, `RandomCodes`, failures.
- Produces:
  - `GroupRepository` (port): `watchMyGroups(userId)`, `watchGroup(id)`, `watchMembers(id)`, `getGroup(id)`, `getMembers(id)`, `createGroup(group, organizer)`, `joinByCode(code, member)`, `updateGroup(group)`, `updateSelfRating(groupId, userId, rating)`, `setOrganizerOverride(groupId, userId, rating?)`.
  - `OrganizerGuard(repo).require(groupId, userId) -> Result<Group>` (fails with `Unauthorized`).
  - Use cases (all callable classes): `CreateGroup(repo, codes)({name, court, organizer})`, `JoinGroupByCode(repo)({code, member})`, `UpdateSelfRating(repo)({groupId, userId, rating})`, `SetOrganizerOverride(repo, guard)({groupId, actingUserId, targetUserId, rating})`, `UpdateGroupSettings(repo, guard)({groupId, actingUserId, court?, radiusMeters?, defaultTeamSize?})`, `WatchMyGroups`, `WatchGroup`, `WatchMembers`.
  - Test support: `Changes` (stream helper) and `FakeGroupRepository` (in-memory; public maps `groups` and `members`).

- [ ] **Step 1: Write the test support and the failing tests**

`test/support/changes.dart`:

```dart
import 'dart:async';

/// Lets in-memory fakes offer `watch*` streams: each subscriber immediately
/// gets the current value and a new one after every [notify].
class Changes {
  final _controller = StreamController<void>.broadcast(sync: true);

  void notify() => _controller.add(null);

  Stream<T> watch<T>(T Function() read) {
    late final StreamController<T> out;
    StreamSubscription<void>? subscription;
    out = StreamController<T>(
      onListen: () {
        out.add(read());
        subscription = _controller.stream.listen((_) => out.add(read()));
      },
      onCancel: () => subscription?.cancel(),
    );
    return out.stream;
  }
}
```

`test/support/fake_group_repository.dart`:

```dart
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
```

`test/features/groups/group_use_cases_test.dart`:

```dart
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
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/groups/group_use_cases_test.dart
```

Expected: FAIL to compile (the repository port and use cases do not exist).

- [ ] **Step 3: Implement**

`lib/features/groups/domain/repositories/group_repository.dart`:

```dart
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';

abstract interface class GroupRepository {
  /// Groups the user belongs to.
  Stream<List<Group>> watchMyGroups(String userId);

  Stream<Group?> watchGroup(String groupId);

  Stream<List<Member>> watchMembers(String groupId);

  Future<Result<Group>> getGroup(String groupId);

  Future<Result<List<Member>>> getMembers(String groupId);

  /// Persists the group, its invite code and the organizer's member document.
  Future<Result<Group>> createGroup(Group group, Member organizer);

  /// Resolves [code] to a group and adds [member] to it.
  /// Fails with `InvalidInviteCode` when the code is unknown.
  Future<Result<Group>> joinByCode(String code, Member member);

  Future<Result<void>> updateGroup(Group group);

  Future<Result<void>> updateSelfRating(String groupId, String userId, int rating);

  Future<Result<void>> setOrganizerOverride(String groupId, String userId, int? rating);
}
```

`lib/features/groups/domain/usecases/organizer_guard.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../repositories/group_repository.dart';

/// Loads a group and checks that [userId] is its organizer.
class OrganizerGuard {
  OrganizerGuard(this._groups);

  final GroupRepository _groups;

  Future<Result<Group>> require(String groupId, String userId) async {
    final result = await _groups.getGroup(groupId);
    if (result.isErr) return result;
    if (result.value.organizerId != userId) {
      return const Err(Unauthorized('Only the organizer can do this'));
    }
    return result;
  }
}
```

`lib/features/groups/domain/usecases/create_group.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/geo.dart';
import '../../../../core/random_codes.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class CreateGroup {
  CreateGroup(this._groups, this._codes);

  final GroupRepository _groups;
  final RandomCodes _codes;

  /// [organizer] carries the creator's identity and self rating; its role is
  /// forced to organizer.
  Future<Result<Group>> call({
    required String name,
    required Coordinates court,
    required Member organizer,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value(const Err(InvalidInput('Name is required')));
    if (!isValidRating(organizer.selfRating)) {
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 5')));
    }
    final group = Group(
      id: _codes.id(),
      name: trimmed,
      organizerId: organizer.userId,
      inviteCode: _codes.inviteCode(),
      court: court,
    );
    return _groups.createGroup(
      group,
      Member(
        userId: organizer.userId,
        displayName: organizer.displayName,
        photoUrl: organizer.photoUrl,
        selfRating: organizer.selfRating,
        role: MemberRole.organizer,
      ),
    );
  }
}
```

`lib/features/groups/domain/usecases/join_group_by_code.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../entities/group.dart';
import '../entities/member.dart';
import '../repositories/group_repository.dart';

class JoinGroupByCode {
  JoinGroupByCode(this._groups);

  final GroupRepository _groups;

  /// [member] carries the joiner's identity and self rating; its role is
  /// forced to player and any override is dropped.
  Future<Result<Group>> call({required String code, required Member member}) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return Future.value(const Err(InvalidInviteCode()));
    if (!isValidRating(member.selfRating)) {
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 5')));
    }
    return _groups.joinByCode(
      normalized,
      Member(
        userId: member.userId,
        displayName: member.displayName,
        photoUrl: member.photoUrl,
        selfRating: member.selfRating,
        role: MemberRole.player,
      ),
    );
  }
}
```

`lib/features/groups/domain/usecases/update_self_rating.dart`:

```dart
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
      return Future.value(const Err(InvalidInput('Rating must be between 1 and 5')));
    }
    return _groups.updateSelfRating(groupId, userId, rating);
  }
}
```

`lib/features/groups/domain/usecases/set_organizer_override.dart`:

```dart
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
```

`lib/features/groups/domain/usecases/update_group_settings.dart`:

```dart
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
```

`lib/features/groups/domain/usecases/watch_groups.dart`:

```dart
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
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/groups test/architecture_test.dart && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(groups): add group repository port and use cases"
```

### Task 7: Sessions domain (port, recurrence and session use cases)

**Files:**
- Create: `lib/features/sessions/domain/repositories/session_repository.dart`, `lib/features/sessions/domain/usecases/{ensure_upcoming_sessions,create_one_off_session,cancel_session,edit_session,update_schedule,watch_sessions}.dart`
- Test: `test/support/fake_session_repository.dart`, `test/features/sessions/session_use_cases_test.dart`

**Interfaces:**
- Consumes: Tasks 2 to 6 (`OrganizerGuard`, `GroupRepository`, `ScheduleExpander`, `GameSession`, ...).
- Produces:
  - `SessionRepository` (port): `watchUpcomingSessions(groupId)`, `watchSession(groupId, sessionId)`, `watchCheckIns(groupId, sessionId)`, `getSession`, `getSessionsStartingAfter(groupId, after)`, `getCheckIns`, `createIfAbsent(groupId, session) -> Result<bool>`, `updateSession`, `deleteSession`, `publishTeams(groupId, sessionId, teams)`, `checkIn(groupId, sessionId, checkIn)`, `checkOut(groupId, sessionId, userId)`.
  - `EnsureUpcomingSessions(groups, sessions, expander, now)({groupId, userId}) -> Result<int>` (sessions created; 0 for non-organizers or no schedule).
  - `UpdateSchedule(groups, sessions, guard, ensure, now)({groupId, actingUserId, schedule}) -> Result<int>`.
  - `CreateOneOffSession(guard, sessions, codes)({groupId, actingUserId, startsAt, teamSize?}) -> Result<GameSession>`.
  - `CancelSession(guard, sessions)({groupId, sessionId, actingUserId})`, `EditSession(guard, sessions)({groupId, sessionId, actingUserId, teamSize?, startsAt?}) -> Result<GameSession>`.
  - `WatchUpcomingSessions`, `WatchSession`, `WatchCheckIns`.
  - Test support: `FakeSessionRepository` (public maps `sessions`, `checkIns`; helper `seed(groupId, session)`).

- [ ] **Step 1: Write the fake and the failing tests**

`test/support/fake_session_repository.dart`:

```dart
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/result.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';
import 'package:volley_teams/features/sessions/domain/repositories/session_repository.dart';

import 'changes.dart';

class FakeSessionRepository implements SessionRepository {
  /// groupId -> sessionId -> session
  final Map<String, Map<String, GameSession>> sessions = {};

  /// "groupId/sessionId" -> userId -> check-in
  final Map<String, Map<String, CheckIn>> checkIns = {};
  final _changes = Changes();

  Map<String, GameSession> _of(String groupId) => sessions.putIfAbsent(groupId, () => {});

  Map<String, CheckIn> _checkInsOf(String groupId, String sessionId) =>
      checkIns.putIfAbsent('$groupId/$sessionId', () => {});

  List<GameSession> _sorted(String groupId) =>
      _of(groupId).values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// Test helper: adds a session directly.
  void seed(String groupId, GameSession session) {
    _of(groupId)[session.id] = session;
    _changes.notify();
  }

  @override
  Stream<List<GameSession>> watchUpcomingSessions(String groupId) =>
      _changes.watch(() => _sorted(groupId));

  @override
  Stream<GameSession?> watchSession(String groupId, String sessionId) =>
      _changes.watch(() => _of(groupId)[sessionId]);

  @override
  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId) =>
      _changes.watch(() => _checkInsOf(groupId, sessionId).values.toList());

  @override
  Future<Result<GameSession>> getSession(String groupId, String sessionId) async {
    final session = _of(groupId)[sessionId];
    return session == null ? const Err(NotFound('session')) : Ok(session);
  }

  @override
  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after) async =>
      Ok(_sorted(groupId).where((s) => s.startsAt.isAfter(after)).toList());

  @override
  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId) async =>
      Ok(_checkInsOf(groupId, sessionId).values.toList());

  @override
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session) async {
    if (_of(groupId).containsKey(session.id)) return const Ok(false);
    _of(groupId)[session.id] = session;
    _changes.notify();
    return const Ok(true);
  }

  @override
  Future<Result<void>> updateSession(String groupId, GameSession session) async {
    _of(groupId)[session.id] = session;
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> deleteSession(String groupId, String sessionId) async {
    _of(groupId).remove(sessionId);
    checkIns.remove('$groupId/$sessionId');
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams) async {
    final session = _of(groupId)[sessionId];
    if (session == null) return const Err(NotFound('session'));
    if (session.status == SessionStatus.teamsPublished) return const Err(SessionAlreadyPublished());
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());
    _of(groupId)[sessionId] = session.copyWith(status: SessionStatus.teamsPublished, teams: teams);
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn) async {
    final session = _of(groupId)[sessionId];
    if (session == null) return const Err(NotFound('session'));
    if (session.status != SessionStatus.scheduled) return const Err(CheckInClosed());
    _checkInsOf(groupId, sessionId)[checkIn.userId] = checkIn;
    _changes.notify();
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> checkOut(String groupId, String sessionId, String userId) async {
    _checkInsOf(groupId, sessionId).remove(userId);
    _changes.notify();
    return const Ok<void>(null);
  }
}
```

`test/features/sessions/session_use_cases_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/random_codes.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/services/schedule_expander.dart';
import 'package:volley_teams/features/sessions/domain/usecases/cancel_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/create_one_off_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/edit_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/ensure_upcoming_sessions.dart';
import 'package:volley_teams/features/sessions/domain/usecases/update_schedule.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_session_repository.dart';

const sundays = Schedule(
  weekdays: {DateTime.sunday},
  startTime: LocalTime(19, 0),
  timezone: 'America/New_York',
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // 2026-03-01 12:00 UTC is a Sunday morning in New York.
  final now = DateTime.utc(2026, 3, 1, 12);
  late FakeGroupRepository groups;
  late FakeSessionRepository sessions;
  late OrganizerGuard guard;
  late EnsureUpcomingSessions ensure;

  Group makeGroup({Schedule? schedule}) => Group(
        id: 'g1', name: 'G', organizerId: 'ana', inviteCode: 'ABCDEFGH',
        court: const Coordinates(1, 1), schedule: schedule,
      );

  setUp(() {
    groups = FakeGroupRepository()..groups['g1'] = makeGroup(schedule: sundays);
    sessions = FakeSessionRepository();
    guard = OrganizerGuard(groups);
    ensure = EnsureUpcomingSessions(groups, sessions, const ScheduleExpander(), () => now);
  });

  group('EnsureUpcomingSessions', () {
    test('creates the next four Sundays with the group defaults', () async {
      final created = await ensure(groupId: 'g1', userId: 'ana');
      expect(created.value, 4);
      final all = sessions.sessions['g1']!;
      expect(all.keys, ['2026-03-01T19:00', '2026-03-08T19:00', '2026-03-15T19:00', '2026-03-22T19:00']);
      expect(all['2026-03-08T19:00']!.teamSize, 6);
      expect(all['2026-03-08T19:00']!.court, const Coordinates(1, 1));
      expect(all['2026-03-08T19:00']!.startsAt, DateTime.utc(2026, 3, 8, 23));
    });

    test('is idempotent and never overwrites an edited or cancelled occurrence', () async {
      await ensure(groupId: 'g1', userId: 'ana');
      final cancelled = sessions.sessions['g1']!['2026-03-08T19:00']!
          .copyWith(status: SessionStatus.cancelled, modified: true);
      sessions.seed('g1', cancelled);

      final again = await ensure(groupId: 'g1', userId: 'ana');
      expect(again.value, 0);
      expect(sessions.sessions['g1']!['2026-03-08T19:00']!.status, SessionStatus.cancelled);
    });

    test('does nothing for a non-organizer or a group without a schedule', () async {
      expect((await ensure(groupId: 'g1', userId: 'bruno')).value, 0);
      groups.groups['g1'] = makeGroup();
      expect((await ensure(groupId: 'g1', userId: 'ana')).value, 0);
      expect(sessions.sessions['g1'] ?? {}, isEmpty);
    });
  });

  group('CreateOneOffSession', () {
    test('creates a modified session from the group defaults, organizer only', () async {
      final useCase = CreateOneOffSession(guard, sessions, RandomCodes(Random(1)));
      final start = DateTime.utc(2026, 3, 10, 22);

      expect((await useCase(groupId: 'g1', actingUserId: 'bruno', startsAt: start)).failure, isA<Unauthorized>());

      final session = (await useCase(groupId: 'g1', actingUserId: 'ana', startsAt: start, teamSize: 4)).value;
      expect(session.modified, isTrue);
      expect(session.teamSize, 4);
      expect(session.startsAt, start);
      expect(sessions.sessions['g1']!.containsKey(session.id), isTrue);
    });
  });

  group('CancelSession and EditSession', () {
    setUp(() async => ensure(groupId: 'g1', userId: 'ana'));

    test('cancelling marks the session cancelled and modified', () async {
      final result = await CancelSession(guard, sessions)(groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'ana');
      expect(result.isOk, isTrue);
      final stored = sessions.sessions['g1']!['2026-03-08T19:00']!;
      expect(stored.status, SessionStatus.cancelled);
      expect(stored.modified, isTrue);
    });

    test('a published session cannot be cancelled or edited', () async {
      final published = sessions.sessions['g1']!['2026-03-08T19:00']!.copyWith(status: SessionStatus.teamsPublished);
      sessions.seed('g1', published);
      expect(
        (await CancelSession(guard, sessions)(groupId: 'g1', sessionId: published.id, actingUserId: 'ana')).failure,
        isA<SessionAlreadyPublished>(),
      );
      expect(
        (await EditSession(guard, sessions)(groupId: 'g1', sessionId: published.id, actingUserId: 'ana', teamSize: 4)).failure,
        isA<SessionAlreadyPublished>(),
      );
    });

    test('editing changes team size and start, moves the window, and marks modified', () async {
      final newStart = DateTime.utc(2026, 3, 8, 22);
      final edited = (await EditSession(guard, sessions)(
        groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'ana', teamSize: 4, startsAt: newStart,
      )).value;
      expect(edited.teamSize, 4);
      expect(edited.startsAt, newStart);
      expect(edited.checkInOpensAt, DateTime.utc(2026, 3, 8, 21));
      expect(edited.modified, isTrue);
      expect(edited.id, '2026-03-08T19:00'); // the id never changes
    });

    test('only the organizer may cancel or edit', () async {
      expect(
        (await CancelSession(guard, sessions)(groupId: 'g1', sessionId: '2026-03-08T19:00', actingUserId: 'bruno')).failure,
        isA<Unauthorized>(),
      );
    });
  });

  group('UpdateSchedule', () {
    test('rebuilds untouched future sessions and keeps edited ones and ones with check-ins', () async {
      await ensure(groupId: 'g1', userId: 'ana'); // Sundays Mar 1, 8, 15, 22
      sessions.seed('g1', sessions.sessions['g1']!['2026-03-15T19:00']!.copyWith(modified: true));
      sessions.checkIns['g1/2026-03-22T19:00'] = {
        'bruno': CheckIn(userId: 'bruno', checkedInAt: now, distanceMeters: 5),
      };

      const saturdays = Schedule(
        weekdays: {DateTime.saturday},
        startTime: LocalTime(10, 0),
        timezone: 'America/New_York',
      );
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      final result = await useCase(groupId: 'g1', actingUserId: 'ana', schedule: saturdays);

      expect(result.isOk, isTrue);
      expect(groups.groups['g1']!.schedule, saturdays);
      final ids = sessions.sessions['g1']!.keys.toSet();
      // Kept: the edited Mar 15 and the Mar 22 one with a check-in.
      expect(ids, containsAll(['2026-03-15T19:00', '2026-03-22T19:00']));
      // Removed: the untouched Sunday Mar 8.
      expect(ids, isNot(contains('2026-03-08T19:00')));
      // Added: the new Saturdays.
      expect(ids, containsAll(['2026-03-07T10:00', '2026-03-14T10:00', '2026-03-21T10:00', '2026-03-28T10:00']));
    });

    test('only the organizer can change the schedule', () async {
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      expect((await useCase(groupId: 'g1', actingUserId: 'bruno', schedule: null)).failure, isA<Unauthorized>());
    });

    test('removing the schedule deletes untouched future sessions and creates none', () async {
      await ensure(groupId: 'g1', userId: 'ana');
      final useCase = UpdateSchedule(groups, sessions, guard, ensure, () => now);
      await useCase(groupId: 'g1', actingUserId: 'ana', schedule: null);
      expect(groups.groups['g1']!.schedule, isNull);
      expect(sessions.sessions['g1']!, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/sessions/session_use_cases_test.dart
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/features/sessions/domain/repositories/session_repository.dart`:

```dart
import '../../../../core/result.dart';
import '../entities/check_in.dart';
import '../entities/game_session.dart';
import '../entities/team.dart';

abstract interface class SessionRepository {
  /// Sessions whose check-in window has not ended more than a day ago,
  /// ordered by start time.
  Stream<List<GameSession>> watchUpcomingSessions(String groupId);

  Stream<GameSession?> watchSession(String groupId, String sessionId);

  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId);

  Future<Result<GameSession>> getSession(String groupId, String sessionId);

  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after);

  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId);

  /// Writes [session] only when no document with its id exists.
  /// Returns true when it was created, false when it already existed.
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session);

  Future<Result<void>> updateSession(String groupId, GameSession session);

  Future<Result<void>> deleteSession(String groupId, String sessionId);

  /// Atomically stores [teams] and sets the status to `teamsPublished`.
  /// Fails with `SessionAlreadyPublished` or `SessionCancelled` when the
  /// session is not `scheduled`.
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams);

  /// Atomically records the check-in. Fails with `CheckInClosed` when the
  /// session is no longer `scheduled`.
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn);

  Future<Result<void>> checkOut(String groupId, String sessionId, String userId);
}
```

`lib/features/sessions/domain/usecases/ensure_upcoming_sessions.dart`:

```dart
import '../../../../core/result.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';
import '../services/schedule_expander.dart';

/// Materializes the group's weekly schedule into concrete sessions.
/// Idempotent: existing sessions (edited, cancelled or not) are never touched.
class EnsureUpcomingSessions {
  EnsureUpcomingSessions(this._groups, this._sessions, this._expander, this._now);

  final GroupRepository _groups;
  final SessionRepository _sessions;
  final ScheduleExpander _expander;
  final DateTime Function() _now;

  /// Returns how many sessions were created. Does nothing (returns 0) for
  /// anyone but the organizer, or when the group has no schedule.
  Future<Result<int>> call({required String groupId, required String userId}) async {
    final groupResult = await _groups.getGroup(groupId);
    if (groupResult.isErr) return groupResult.castErr();
    final group = groupResult.value;
    final schedule = group.schedule;
    if (group.organizerId != userId || schedule == null) return const Ok(0);

    var created = 0;
    for (final occurrence in _expander.expand(schedule: schedule, now: _now())) {
      final result = await _sessions.createIfAbsent(
        groupId,
        GameSession.scheduled(
          id: occurrence.id,
          startsAt: occurrence.startsAt,
          teamSize: group.defaultTeamSize,
          court: group.court,
          radiusMeters: group.radiusMeters,
        ),
      );
      if (result.isErr) return result.castErr();
      if (result.value) created++;
    }
    return Ok(created);
  }
}
```

`lib/features/sessions/domain/usecases/create_one_off_session.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/random_codes.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class CreateOneOffSession {
  CreateOneOffSession(this._guard, this._sessions, this._codes);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;
  final RandomCodes _codes;

  Future<Result<GameSession>> call({
    required String groupId,
    required String actingUserId,
    required DateTime startsAt,
    int? teamSize,
  }) async {
    if (teamSize != null && teamSize < 2) {
      return const Err(InvalidInput('A team needs at least 2 players'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final group = guard.value;
    // `modified: true` keeps the recurring schedule from ever replacing it.
    final session = GameSession.scheduled(
      id: 'one-off-${_codes.id(12)}',
      startsAt: startsAt.toUtc(),
      teamSize: teamSize ?? group.defaultTeamSize,
      court: group.court,
      radiusMeters: group.radiusMeters,
      modified: true,
    );
    final written = await _sessions.createIfAbsent(groupId, session);
    return written.isErr ? written.castErr() : Ok(session);
  }
}
```

`lib/features/sessions/domain/usecases/cancel_session.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class CancelSession {
  CancelSession(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found.castErr();
    final session = found.value;
    if (session.status == SessionStatus.teamsPublished) {
      return const Err(SessionAlreadyPublished());
    }
    if (session.status == SessionStatus.cancelled) return const Ok<void>(null);
    return _sessions.updateSession(
      groupId,
      session.copyWith(status: SessionStatus.cancelled, modified: true),
    );
  }
}
```

`lib/features/sessions/domain/usecases/edit_session.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

/// Changes one occurrence (team size and/or start time) without touching the
/// schedule. The session is marked `modified` so the schedule leaves it alone.
class EditSession {
  EditSession(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<GameSession>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    int? teamSize,
    DateTime? startsAt,
  }) async {
    if (teamSize != null && teamSize < 2) {
      return const Err(InvalidInput('A team needs at least 2 players'));
    }
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found;
    final session = found.value;
    if (session.status == SessionStatus.teamsPublished) {
      return const Err(SessionAlreadyPublished());
    }
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());

    final updated = session.copyWith(
      teamSize: teamSize,
      startsAt: startsAt?.toUtc(),
      modified: true,
    );
    final written = await _sessions.updateSession(groupId, updated);
    return written.isErr ? written.castErr() : Ok(updated);
  }
}
```

`lib/features/sessions/domain/usecases/update_schedule.dart`:

```dart
import '../../../../core/result.dart';
import '../../../groups/domain/entities/schedule.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';
import 'ensure_upcoming_sessions.dart';

/// Saves a new weekly schedule (or removes it with `null`) and rebuilds the
/// future sessions that the old schedule created.
class UpdateSchedule {
  UpdateSchedule(this._groups, this._sessions, this._guard, this._ensure, this._now);

  final GroupRepository _groups;
  final SessionRepository _sessions;
  final OrganizerGuard _guard;
  final EnsureUpcomingSessions _ensure;
  final DateTime Function() _now;

  Future<Result<int>> call({
    required String groupId,
    required String actingUserId,
    required Schedule? schedule,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();

    final saved = await _groups.updateGroup(guard.value.copyWith(schedule: () => schedule));
    if (saved.isErr) return saved.castErr();

    // Remove future occurrences created by the old rule: still scheduled,
    // never edited, and with nobody checked in.
    final future = await _sessions.getSessionsStartingAfter(groupId, _now());
    if (future.isErr) return future.castErr();
    for (final session in future.value) {
      if (session.status != SessionStatus.scheduled || session.modified) continue;
      final checkIns = await _sessions.getCheckIns(groupId, session.id);
      if (checkIns.isErr) return checkIns.castErr();
      if (checkIns.value.isNotEmpty) continue;
      final deleted = await _sessions.deleteSession(groupId, session.id);
      if (deleted.isErr) return deleted.castErr();
    }
    return _ensure(groupId: groupId, userId: actingUserId);
  }
}
```

`lib/features/sessions/domain/usecases/watch_sessions.dart`:

```dart
import '../entities/check_in.dart';
import '../entities/game_session.dart';
import '../repositories/session_repository.dart';

class WatchUpcomingSessions {
  WatchUpcomingSessions(this._sessions);

  final SessionRepository _sessions;

  Stream<List<GameSession>> call(String groupId) => _sessions.watchUpcomingSessions(groupId);
}

class WatchSession {
  WatchSession(this._sessions);

  final SessionRepository _sessions;

  Stream<GameSession?> call(String groupId, String sessionId) =>
      _sessions.watchSession(groupId, sessionId);
}

class WatchCheckIns {
  WatchCheckIns(this._sessions);

  final SessionRepository _sessions;

  Stream<List<CheckIn>> call(String groupId, String sessionId) =>
      _sessions.watchCheckIns(groupId, sessionId);
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/sessions test/architecture_test.dart && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(sessions): add session repository port, recurrence and session use cases"
```

### Task 8: Check-in use cases

**Files:**
- Create: `lib/features/sessions/domain/usecases/{check_in_to_session,check_out_of_session}.dart`
- Test: `test/support/fake_location_provider.dart`, `test/features/sessions/check_in_test.dart`

**Interfaces:**
- Consumes: `SessionRepository`, `LocationProvider`, `distanceMeters`, `OrganizerGuard`.
- Produces: `CheckInToSession(sessions, location, now)({groupId, sessionId, userId}) -> Result<CheckIn>` (fails with `CheckInClosed`, `LocationPermissionDenied`, `MockLocationDetected`, `NotInGeofence`); `CheckOutOfSession(sessions)({groupId, sessionId, userId})`; `RemoveCheckIn(guard, sessions)({groupId, sessionId, actingUserId, targetUserId})`; test fake `FakeLocationProvider` (settable `position` and `failure`).

- [ ] **Step 1: Write the fake and the failing tests**

`test/support/fake_location_provider.dart`:

```dart
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/core/result.dart';

class FakeLocationProvider implements LocationProvider {
  FakeLocationProvider([this.position = const DevicePosition(coordinates: Coordinates(0, 0))]);

  DevicePosition position;
  Failure? failure;

  @override
  Future<Result<DevicePosition>> currentPosition() async =>
      failure != null ? Err(failure!) : Ok(position);
}
```

`test/features/sessions/check_in_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/check_in_to_session.dart';
import 'package:volley_teams/features/sessions/domain/usecases/check_out_of_session.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_location_provider.dart';
import '../../support/fake_session_repository.dart';

void main() {
  const court = Coordinates(0, 0);
  final start = DateTime.utc(2026, 9, 22, 22);
  late FakeSessionRepository sessions;
  late FakeLocationProvider location;
  late DateTime now;
  late CheckInToSession checkIn;

  setUp(() {
    now = DateTime.utc(2026, 9, 22, 21, 30); // inside the window
    sessions = FakeSessionRepository()
      ..seed(
        'g1',
        GameSession.scheduled(id: 's1', startsAt: start, teamSize: 6, court: court, radiusMeters: 150),
      );
    location = FakeLocationProvider();
    checkIn = CheckInToSession(sessions, location, () => now);
  });

  Future<dynamic> attempt() => checkIn(groupId: 'g1', sessionId: 's1', userId: 'ana');

  test('records the check-in with the measured distance when inside the radius', () async {
    // About 55 m north of the court.
    location.position = const DevicePosition(coordinates: Coordinates(0.0005, 0));
    final result = await attempt();
    expect(result.isOk, isTrue);
    expect(result.value.distanceMeters, closeTo(55.6, 1));
    expect(sessions.checkIns['g1/s1']!['ana'], isNotNull);
  });

  test('outside the radius fails with NotInGeofence and writes nothing', () async {
    location.position = const DevicePosition(coordinates: Coordinates(0.002, 0)); // ~222 m
    final result = await attempt();
    expect(result.failure, isA<NotInGeofence>());
    expect((result.failure as NotInGeofence).radiusMeters, 150);
    expect(sessions.checkIns['g1/s1'] ?? {}, isEmpty);
  });

  test('a mocked location is rejected', () async {
    location.position = const DevicePosition(coordinates: court, isMocked: true);
    expect((await attempt()).failure, isA<MockLocationDetected>());
  });

  test('a denied permission is passed through', () async {
    location.failure = const LocationPermissionDenied();
    expect((await attempt()).failure, isA<LocationPermissionDenied>());
  });

  test('before the window opens and after it closes, check-in is closed', () async {
    now = DateTime.utc(2026, 9, 22, 20, 59);
    expect((await attempt()).failure, isA<CheckInClosed>());
    now = DateTime.utc(2026, 9, 23, 1, 1);
    expect((await attempt()).failure, isA<CheckInClosed>());
  });

  test('a published or cancelled session is closed', () async {
    sessions.seed('g1', sessions.sessions['g1']!['s1']!.copyWith(status: SessionStatus.cancelled));
    expect((await attempt()).failure, isA<CheckInClosed>());
  });

  test('check-out removes the player; the organizer can remove anyone', () async {
    await attempt();
    await CheckOutOfSession(sessions)(groupId: 'g1', sessionId: 's1', userId: 'ana');
    expect(sessions.checkIns['g1/s1']!, isEmpty);

    await attempt();
    final groups = FakeGroupRepository()
      ..groups['g1'] = const Group(id: 'g1', name: 'G', organizerId: 'boss', inviteCode: 'X', court: court);
    final remove = RemoveCheckIn(OrganizerGuard(groups), sessions);
    expect((await remove(groupId: 'g1', sessionId: 's1', actingUserId: 'ana', targetUserId: 'ana')).failure, isA<Unauthorized>());
    expect((await remove(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', targetUserId: 'ana')).isOk, isTrue);
    expect(sessions.checkIns['g1/s1']!, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/sessions/check_in_test.dart
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/features/sessions/domain/usecases/check_in_to_session.dart`:

```dart
import '../../../../core/failure.dart';
import '../../../../core/geo.dart';
import '../../../../core/location_provider.dart';
import '../../../../core/result.dart';
import '../entities/check_in.dart';
import '../repositories/session_repository.dart';

class CheckInToSession {
  CheckInToSession(this._sessions, this._location, this._now);

  final SessionRepository _sessions;
  final LocationProvider _location;
  final DateTime Function() _now;

  Future<Result<CheckIn>> call({
    required String groupId,
    required String sessionId,
    required String userId,
  }) async {
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found.castErr();
    final session = found.value;
    if (!session.isCheckInOpen(_now())) return const Err(CheckInClosed());

    final position = await _location.currentPosition();
    if (position.isErr) return position.castErr();
    if (position.value.isMocked) return const Err(MockLocationDetected());

    final distance = distanceMeters(position.value.coordinates, session.court);
    if (distance > session.radiusMeters) {
      return Err(NotInGeofence(distanceMeters: distance, radiusMeters: session.radiusMeters));
    }

    final checkIn = CheckIn(
      userId: userId,
      checkedInAt: _now().toUtc(),
      distanceMeters: distance,
    );
    final written = await _sessions.checkIn(groupId, sessionId, checkIn);
    return written.isErr ? written.castErr() : Ok(checkIn);
  }
}
```

`lib/features/sessions/domain/usecases/check_out_of_session.dart`:

```dart
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../repositories/session_repository.dart';

class CheckOutOfSession {
  CheckOutOfSession(this._sessions);

  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String userId,
  }) =>
      _sessions.checkOut(groupId, sessionId, userId);
}

/// Organizer removes someone else's check-in (a misclick or a suspicious one).
class RemoveCheckIn {
  RemoveCheckIn(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    required String targetUserId,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _sessions.checkOut(groupId, sessionId, targetUserId);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/sessions test/architecture_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(sessions): add geofenced check-in, check-out and organizer removal"
```

### Task 9: Generate and publish teams

**Files:**
- Create: `lib/features/teams/domain/usecases/{generate_teams,publish_teams}.dart`
- Test: `test/features/teams/team_use_cases_test.dart`

**Interfaces:**
- Consumes: `TeamBalancer`, `RatedPlayer` (Task 4), `GroupRepository.getMembers`, `SessionRepository.getSession/getCheckIns/publishTeams`, `OrganizerGuard`.
- Produces: `GenerateTeams(guard, groups, sessions, balancer, random)({groupId, sessionId, actingUserId}) -> Result<List<Team>>` (a preview; nothing is persisted); `PublishTeams(guard, sessions)({groupId, sessionId, actingUserId, teams}) -> Result<void>`.

- [ ] **Step 1: Write the failing tests**

`test/features/teams/team_use_cases_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/usecases/organizer_guard.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/teams/domain/services/team_balancer.dart';
import 'package:volley_teams/features/teams/domain/usecases/generate_teams.dart';
import 'package:volley_teams/features/teams/domain/usecases/publish_teams.dart';

import '../../support/fake_group_repository.dart';
import '../../support/fake_session_repository.dart';

void main() {
  final start = DateTime.utc(2026, 9, 22, 22);
  late FakeGroupRepository groups;
  late FakeSessionRepository sessions;
  late OrganizerGuard guard;

  Member player(String id, int rating, {int? override}) => Member(
        userId: id, displayName: id, selfRating: rating,
        organizerOverride: override, role: MemberRole.player,
      );

  GenerateTeams generate() => GenerateTeams(guard, groups, sessions, const TeamBalancer(), Random(5));

  setUp(() {
    groups = FakeGroupRepository()
      ..groups['g1'] = const Group(
        id: 'g1', name: 'G', organizerId: 'boss', inviteCode: 'X', court: Coordinates(0, 0),
      );
    groups.members['g1'] = {
      for (final m in [
        player('a', 5), player('b', 5), player('c', 3), player('d', 3),
        player('e', 1, override: 4), player('f', 2), player('g', 2), player('h', 1),
        player('absent', 5),
      ])
        m.userId: m,
    };
    guard = OrganizerGuard(groups);
    sessions = FakeSessionRepository()
      ..seed('g1', GameSession.scheduled(
        id: 's1', startsAt: start, teamSize: 4,
        court: const Coordinates(0, 0), radiusMeters: 150,
      ));
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
      sessions.checkIns.putIfAbsent('g1/s1', () => {})[id] =
          CheckIn(userId: id, checkedInAt: start, distanceMeters: 1);
    }
  });

  test('balances only players who checked in, using effective ratings', () async {
    final teams = (await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).value;
    expect(teams, hasLength(2));
    final ids = teams.expand((t) => t.playerIds).toSet();
    expect(ids, {'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'}); // not 'absent'
    // The two 5s are on different teams.
    final teamOf = {for (final t in teams) for (final id in t.playerIds) id: t.index};
    expect(teamOf['a'], isNot(teamOf['b']));
    // 'e' is rated 1 but overridden to 4: the two totals reflect that.
    expect(teams.fold<int>(0, (s, t) => s + t.ratingTotal), 5 + 5 + 3 + 3 + 4 + 2 + 2 + 1);
  });

  test('only the organizer can generate, and fewer than four players is rejected', () async {
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'a')).failure, isA<Unauthorized>());
    sessions.checkIns['g1/s1'] = {
      for (final id in ['a', 'b', 'c']) id: CheckIn(userId: id, checkedInAt: start, distanceMeters: 1),
    };
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<NotEnoughPlayers>());
  });

  test('publishing stores the teams and closes the session; a second publish fails', () async {
    final teams = (await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).value;
    final publish = PublishTeams(guard, sessions);

    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'a', teams: teams)).failure, isA<Unauthorized>());
    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', teams: teams)).isOk, isTrue);
    final stored = sessions.sessions['g1']!['s1']!;
    expect(stored.status, SessionStatus.teamsPublished);
    expect(stored.teams, teams);

    expect((await publish(groupId: 'g1', sessionId: 's1', actingUserId: 'boss', teams: teams)).failure, isA<SessionAlreadyPublished>());
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<SessionAlreadyPublished>());
  });

  test('a cancelled session cannot generate teams', () async {
    sessions.seed('g1', sessions.sessions['g1']!['s1']!.copyWith(status: SessionStatus.cancelled));
    expect((await generate()(groupId: 'g1', sessionId: 's1', actingUserId: 'boss')).failure, isA<SessionCancelled>());
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/teams/team_use_cases_test.dart
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/features/teams/domain/usecases/generate_teams.dart`:

```dart
import 'dart:math';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../groups/domain/repositories/group_repository.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../../../sessions/domain/entities/game_session.dart';
import '../../../sessions/domain/entities/team.dart';
import '../../../sessions/domain/repositories/session_repository.dart';
import '../services/team_balancer.dart';

/// Builds a team preview from the current check-ins. Nothing is persisted;
/// call it again for a reshuffle.
class GenerateTeams {
  GenerateTeams(this._guard, this._groups, this._sessions, this._balancer, this._random);

  final OrganizerGuard _guard;
  final GroupRepository _groups;
  final SessionRepository _sessions;
  final TeamBalancer _balancer;
  final Random _random;

  Future<Result<List<Team>>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    final found = await _sessions.getSession(groupId, sessionId);
    if (found.isErr) return found.castErr();
    final session = found.value;
    if (session.status == SessionStatus.teamsPublished) {
      return const Err(SessionAlreadyPublished());
    }
    if (session.status == SessionStatus.cancelled) return const Err(SessionCancelled());

    final checkIns = await _sessions.getCheckIns(groupId, sessionId);
    if (checkIns.isErr) return checkIns.castErr();
    final members = await _groups.getMembers(groupId);
    if (members.isErr) return members.castErr();

    final ratings = {for (final m in members.value) m.userId: m.effectiveRating};
    // A stable order keeps seeded runs reproducible.
    final ordered = [...checkIns.value]..sort((a, b) {
        final byTime = a.checkedInAt.compareTo(b.checkedInAt);
        return byTime != 0 ? byTime : a.userId.compareTo(b.userId);
      });
    final players = [
      for (final c in ordered)
        if (ratings[c.userId] != null) RatedPlayer(id: c.userId, rating: ratings[c.userId]!),
    ];
    return _balancer.balance(players: players, teamSize: session.teamSize, random: _random);
  }
}
```

`lib/features/teams/domain/usecases/publish_teams.dart`:

```dart
import '../../../../core/result.dart';
import '../../../groups/domain/usecases/organizer_guard.dart';
import '../../../sessions/domain/entities/team.dart';
import '../../../sessions/domain/repositories/session_repository.dart';

class PublishTeams {
  PublishTeams(this._guard, this._sessions);

  final OrganizerGuard _guard;
  final SessionRepository _sessions;

  Future<Result<void>> call({
    required String groupId,
    required String sessionId,
    required String actingUserId,
    required List<Team> teams,
  }) async {
    final guard = await _guard.require(groupId, actingUserId);
    if (guard.isErr) return guard.castErr();
    return _sessions.publishTeams(groupId, sessionId, teams);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/teams test/architecture_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(teams): add GenerateTeams preview and PublishTeams use cases"
```

### Task 10: Auth domain

**Files:**
- Create: `lib/features/auth/domain/entities/app_user.dart`, `lib/features/auth/domain/repositories/auth_repository.dart`, `lib/features/auth/domain/usecases/auth_use_cases.dart`
- Test: `test/support/fake_auth_repository.dart` (exercised by the widget tests in Task 19)

**Interfaces:**
- Produces: `AppUser(uid, displayName, photoUrl?)`; `AuthRepository` (`watchUser()`, `signInWithGoogle() -> Result<AppUser>`, `signOut()`); `SignInWithGoogle`, `SignOut`, `WatchAuthState` (thin pass-through use cases); `FakeAuthRepository({signedIn})` with `FakeAuthRepository.defaultUser` (uid `ana`).

These use cases only delegate, so they have no unit tests of their own; the sign-in flow is covered end to end by the widget tests in Task 19.

- [ ] **Step 1: Implement**

`lib/features/auth/domain/entities/app_user.dart`:

```dart
import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({required this.uid, required this.displayName, this.photoUrl});

  final String uid;
  final String displayName;
  final String? photoUrl;

  @override
  List<Object?> get props => [uid, displayName, photoUrl];
}
```

`lib/features/auth/domain/repositories/auth_repository.dart`:

```dart
import '../../../../core/result.dart';
import '../entities/app_user.dart';

abstract interface class AuthRepository {
  /// Emits the signed-in user, or null when signed out.
  Stream<AppUser?> watchUser();

  Future<Result<AppUser>> signInWithGoogle();

  Future<void> signOut();
}
```

`lib/features/auth/domain/usecases/auth_use_cases.dart`:

```dart
import '../../../../core/result.dart';
import '../entities/app_user.dart';
import '../repositories/auth_repository.dart';

class SignInWithGoogle {
  SignInWithGoogle(this._auth);

  final AuthRepository _auth;

  Future<Result<AppUser>> call() => _auth.signInWithGoogle();
}

class SignOut {
  SignOut(this._auth);

  final AuthRepository _auth;

  Future<void> call() => _auth.signOut();
}

class WatchAuthState {
  WatchAuthState(this._auth);

  final AuthRepository _auth;

  Stream<AppUser?> call() => _auth.watchUser();
}
```

`test/support/fake_auth_repository.dart`:

```dart
import 'dart:async';

import 'package:volley_teams/core/result.dart';
import 'package:volley_teams/features/auth/domain/entities/app_user.dart';
import 'package:volley_teams/features/auth/domain/repositories/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? signedIn}) : _user = signedIn;

  static const defaultUser = AppUser(uid: 'ana', displayName: 'Ana');

  AppUser? _user;
  final _controller = StreamController<AppUser?>.broadcast(sync: true);

  @override
  Stream<AppUser?> watchUser() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<Result<AppUser>> signInWithGoogle() async {
    _user = defaultUser;
    _controller.add(_user);
    return const Ok(defaultUser);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze && flutter test
```

Expected: `No issues found!` and every test passes.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(auth): add auth domain ports and use cases"
```

---

## Phase 2: Firebase and the data layer

### Task 11: Firebase project wiring (manual setup)

**Files:**
- Create: `lib/firebase_config.dart`, `lib/main.dart` (temporary), plus files generated by `flutterfire configure` (`lib/firebase_options.dart`, `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`)
- Modify: `ios/Runner/Info.plist`

**Interfaces:**
- Produces: a Firebase project the app can talk to; `googleServerClientId` (compile-time constant read from `--dart-define=GOOGLE_SERVER_CLIENT_ID`); `DefaultFirebaseOptions.currentPlatform`.

This task needs the project owner's Google account and cannot be automated. Do the steps in order and stop for the owner where noted.

- [ ] **Step 1: Create the Firebase project and enable services (owner, in the Firebase console)**

1. Create a project (Google Analytics is optional; the app does not use it).
2. **Build > Authentication > Get started > Sign-in method > Google > Enable.** Pick a support email and save. Then open the Google provider again and copy the **Web client ID** (under "Web SDK configuration"). It looks like `1234-abc.apps.googleusercontent.com`. You will pass it as `GOOGLE_SERVER_CLIENT_ID`.
3. **Build > Firestore Database > Create database.** Choose a region near your players and start in **production mode**. (The real rules are deployed in Task 12.)

- [ ] **Step 2: Install the command-line tools**

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

- [ ] **Step 3: Generate the Firebase configuration**

```bash
flutterfire configure --project=<YOUR_PROJECT_ID> --platforms=android,ios --yes
```

Expected: it registers an Android app and an iOS app and creates `lib/firebase_options.dart`, `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`. Check that the Android `applicationId` (in `android/app/build.gradle.kts`) and the iOS bundle id match the ones it registered.

- [ ] **Step 4: Register the Android debug fingerprint (owner)**

```bash
cd android && ./gradlew signingReport && cd ..
```

Copy the `SHA1` of the `debug` variant. In the Firebase console go to **Project settings > Your apps > Android app > Add fingerprint** and paste it. Then re-run `flutterfire configure` so `google-services.json` includes the OAuth client. Google sign-in fails on Android without this step.

- [ ] **Step 5: Add the iOS Google sign-in URL scheme**

Open `ios/Runner/GoogleService-Info.plist`, copy the value of `REVERSED_CLIENT_ID`, and add this inside the top-level `<dict>` of `ios/Runner/Info.plist` (replace the placeholder):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>REPLACE_WITH_REVERSED_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

- [ ] **Step 6: Add the config constant and a temporary entry point**

`lib/firebase_config.dart`:

```dart
/// The "Web client ID" of the Firebase project's Google sign-in provider.
/// Pass it with `--dart-define=GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
```

Replace `lib/main.dart` with this throwaway smoke test (the real one arrives in Task 19):

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Firebase ready')))));
}
```

- [ ] **Step 7: Run it**

```bash
flutter run
```

Expected: the app shows "Firebase ready" with no `[core/no-app]` or `[core/duplicate-app]` error in the console.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "chore: wire Firebase project (options, Android/iOS config, smoke-test main)"
```

### Task 12: Firestore Security Rules and their emulator tests

**Files:**
- Create: `firebase.json`, `firestore.indexes.json`, `firestore.rules`, `rules-tests/package.json`, `rules-tests/firestore.rules.test.mjs`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the Firestore layout from the spec (`groups`, `members`, `sessions`, `checkins`, `inviteCodes`).
- Produces: deployed rules that enforce, server-side, everything a modified client must not be able to do (see spec section 8), plus the collection-group access "My groups" needs.

Prerequisites: Node 18+ and a JDK (21 recommended) for the Firestore emulator.

- [ ] **Step 1: Add the Firebase config and the test project**

`firebase.json`:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "emulators": {
    "firestore": { "host": "127.0.0.1", "port": 8080 },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
```

`firestore.indexes.json`:

```json
{
  "indexes": [],
  "fieldOverrides": [
    {
      "collectionGroup": "members",
      "fieldPath": "userId",
      "indexes": [
        { "order": "ASCENDING", "queryScope": "COLLECTION" },
        { "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }
      ]
    }
  ]
}
```

`rules-tests/package.json`:

```json
{
  "name": "volley-teams-rules-tests",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "firebase emulators:exec --config ../firebase.json --only firestore --project demo-volley-teams \"node --test\""
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^4.0.1",
    "firebase": "^11.0.0",
    "firebase-tools": "^14.27.0"
  }
}
```

Append to `.gitignore`:

```
rules-tests/node_modules/
firestore-debug.log
ui-debug.log
```

```bash
cd rules-tests && npm install && cd ..
```

- [ ] **Step 2: Write the failing rules tests**

`rules-tests/firestore.rules.test.mjs`:

```javascript
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
// s3 = already published.
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
```

- [ ] **Step 3: Start from deny-all and watch the tests fail**

Create `firestore.rules` with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

```bash
cd rules-tests && npm test
```

Expected: most tests FAIL (every `assertSucceeds` is denied).

- [ ] **Step 4: Write the real rules**

`firestore.rules`:

```text
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function groupPath(groupId) {
      return /databases/$(database)/documents/groups/$(groupId);
    }

    function memberPath(groupId, userId) {
      return /databases/$(database)/documents/groups/$(groupId)/members/$(userId);
    }

    function sessionPath(groupId, sessionId) {
      return /databases/$(database)/documents/groups/$(groupId)/sessions/$(sessionId);
    }

    function isMember(groupId) {
      return signedIn() && exists(memberPath(groupId, request.auth.uid));
    }

    function isOrganizer(groupId) {
      return signedIn() && get(groupPath(groupId)).data.organizerId == request.auth.uid;
    }

    function validRating(value) {
      return value is int && value >= 1 && value <= 5;
    }

    function onlyChanges(keys) {
      return request.resource.data.diff(resource.data).affectedKeys().hasOnly(keys);
    }

    // Joining: clients may `get` a code (never list codes).
    match /inviteCodes/{code} {
      allow get: if signedIn();
      allow create: if signedIn()
        && getAfter(groupPath(request.resource.data.groupId)).data.organizerId == request.auth.uid;
    }

    match /groups/{groupId} {
      allow read: if isMember(groupId);
      allow create: if signedIn() && request.resource.data.organizerId == request.auth.uid;
      allow update: if isOrganizer(groupId)
        && request.resource.data.organizerId == resource.data.organizerId;
      allow delete: if isOrganizer(groupId);

      match /members/{userId} {
        allow read: if isMember(groupId);

        allow create: if signedIn()
          && request.auth.uid == userId
          && validRating(request.resource.data.selfRating)
          && (
            // The group creator's own document, written in the same batch as the group.
            (request.resource.data.role == 'organizer'
              && getAfter(groupPath(groupId)).data.organizerId == userId)
            // A player joining with a valid invite code.
            || (request.resource.data.role == 'player'
              && request.resource.data.get('organizerOverride', null) == null
              && get(/databases/$(database)/documents/inviteCodes/$(request.resource.data.inviteCode)).data.groupId == groupId)
          );

        allow update: if signedIn() && (
          (request.auth.uid == userId
            && onlyChanges(['selfRating'])
            && validRating(request.resource.data.selfRating))
          || (isOrganizer(groupId)
            && onlyChanges(['organizerOverride'])
            && (request.resource.data.organizerOverride == null
              || validRating(request.resource.data.organizerOverride)))
        );

        // The organizer cannot leave or be removed in v1.
        allow delete: if signedIn()
          && resource.data.role != 'organizer'
          && (request.auth.uid == userId || isOrganizer(groupId));
      }

      match /sessions/{sessionId} {
        allow read: if isMember(groupId);
        allow create: if isOrganizer(groupId) && request.resource.data.status == 'scheduled';
        // Teams can be published only from `scheduled`.
        allow update: if isOrganizer(groupId)
          && (request.resource.data.status != 'teamsPublished'
            || resource.data.status == 'scheduled');
        allow delete: if isOrganizer(groupId);

        match /checkins/{userId} {
          allow read: if isMember(groupId);

          allow create, update: if signedIn()
            && request.auth.uid == userId
            && isMember(groupId)
            && get(sessionPath(groupId, sessionId)).data.status == 'scheduled'
            && request.time >= get(sessionPath(groupId, sessionId)).data.checkInOpensAt
            && request.time <= get(sessionPath(groupId, sessionId)).data.checkInClosesAt;

          allow delete: if signedIn() && (
            (request.auth.uid == userId
              && get(sessionPath(groupId, sessionId)).data.status == 'scheduled')
            || isOrganizer(groupId)
          );
        }
      }
    }

    // "My groups": collection-group query over the caller's own member documents.
    match /{path=**}/members/{userId} {
      allow read: if signedIn() && resource.data.userId == request.auth.uid;
    }
  }
}
```

- [ ] **Step 5: Run the tests**

```bash
cd rules-tests && npm test
```

Expected: `tests 22`, `pass 22`, `fail 0`. The many `PERMISSION_DENIED` lines in the log are the denial cases (`assertFails`) working as intended.

- [ ] **Step 6: Deploy the rules and index (owner)**

```bash
firebase deploy --only firestore:rules,firestore:indexes --project <YOUR_PROJECT_ID>
```

Expected: `Deploy complete!`. Until this runs, the real database still has the production-mode deny-all rules, and the app cannot read or write.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(firebase): add Firestore Security Rules with emulator tests"
```

### Task 13: Firestore group repository

**Files:**
- Create: `lib/core/data/firestore_guard.dart`, `lib/features/groups/data/group_mapper.dart`, `lib/features/groups/data/firestore_group_repository.dart`
- Test: `test/features/groups/data/firestore_group_repository_test.dart`

**Interfaces:**
- Consumes: `GroupRepository` (Task 6), Firestore layout from Task 12.
- Produces: `guardFirestore` / `guardFirestoreResult` (exception-to-`Failure` translation, reused in Task 14); `groupToMap/groupFromMap`, `scheduleToMap/scheduleFromMap`, `memberToMap(member, {inviteCode})/memberFromMap`; `FirestoreGroupRepository(FirebaseFirestore)`.

Design notes the tests pin down: joining is idempotent (it never overwrites an existing member's rating or override), creating and joining use transactions, and `watchMyGroups` uses a collection-group query on `members.userId`.

- [ ] **Step 1: Write the failing tests**

`test/features/groups/data/firestore_group_repository_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/data/firestore_group_repository.dart';
import 'package:volley_teams/features/groups/data/group_mapper.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';

const ana = Member(userId: 'ana', displayName: 'Ana', photoUrl: 'http://x/a.png', selfRating: 4, role: MemberRole.organizer);
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
      await repo.joinByCode('ABCD2345', bruno.copyWith(selfRating: 5));
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
      await repo.updateSelfRating('g1', 'bruno', 5);
      await repo.setOrganizerOverride('g1', 'bruno', 1);
      final members = (await repo.getMembers('g1')).value;
      final updated = members.firstWhere((m) => m.userId == 'bruno');
      expect(updated.selfRating, 5);
      expect(updated.effectiveRating, 1);

      await repo.setOrganizerOverride('g1', 'bruno', null);
      expect((await repo.watchMembers('g1').first).firstWhere((m) => m.userId == 'bruno').effectiveRating, 5);
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
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/groups/data
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/core/data/firestore_guard.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../failure.dart';
import '../result.dart';

/// Runs [body], turning Firestore and unexpected exceptions into failures so
/// they never cross the data-layer boundary.
Future<Result<T>> guardFirestoreResult<T>(Future<Result<T>> Function() body) async {
  try {
    return await body();
  } on FirebaseException catch (e) {
    return Err(_failureFor(e));
  } catch (e) {
    return Err(Unexpected('$e'));
  }
}

/// Like [guardFirestoreResult] for a body that simply returns a value.
Future<Result<T>> guardFirestore<T>(Future<T> Function() body) =>
    guardFirestoreResult(() async => Ok(await body()));

Failure _failureFor(FirebaseException e) => switch (e.code) {
      'permission-denied' => Unauthorized(e.message),
      'unavailable' || 'deadline-exceeded' => const Offline(),
      'not-found' => NotFound(e.message ?? 'document'),
      _ => Unexpected(e.message ?? e.code),
    };
```

`lib/features/groups/data/group_mapper.dart`:

```dart
import '../../../core/geo.dart';
import '../domain/entities/group.dart';
import '../domain/entities/member.dart';
import '../domain/entities/schedule.dart';

Map<String, Object?> groupToMap(Group group) => {
      'name': group.name,
      'organizerId': group.organizerId,
      'inviteCode': group.inviteCode,
      'courtLat': group.court.latitude,
      'courtLng': group.court.longitude,
      'radiusMeters': group.radiusMeters,
      'defaultTeamSize': group.defaultTeamSize,
      'schedule': group.schedule == null ? null : scheduleToMap(group.schedule!),
    };

Group groupFromMap(String id, Map<String, dynamic> data) => Group(
      id: id,
      name: data['name'] as String,
      organizerId: data['organizerId'] as String,
      inviteCode: data['inviteCode'] as String,
      court: Coordinates(
        (data['courtLat'] as num).toDouble(),
        (data['courtLng'] as num).toDouble(),
      ),
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? Group.standardRadiusMeters,
      defaultTeamSize: (data['defaultTeamSize'] as num?)?.toInt() ?? Group.standardTeamSize,
      schedule: data['schedule'] == null
          ? null
          : scheduleFromMap(Map<String, dynamic>.from(data['schedule'] as Map)),
    );

Map<String, Object?> scheduleToMap(Schedule schedule) {
  final end = schedule.endDate;
  return {
    'weekdays': schedule.weekdays.toList()..sort(),
    'startHour': schedule.startTime.hour,
    'startMinute': schedule.startTime.minute,
    // A plain calendar date, so no timezone can shift it.
    'endDate': end == null ? null : _dateString(end),
    'timezone': schedule.timezone,
  };
}

Schedule scheduleFromMap(Map<String, dynamic> data) {
  final end = data['endDate'] as String?;
  return Schedule(
    weekdays: {for (final d in data['weekdays'] as List) (d as num).toInt()},
    startTime: LocalTime(
      (data['startHour'] as num).toInt(),
      (data['startMinute'] as num).toInt(),
    ),
    endDate: end == null ? null : DateTime.parse(end),
    timezone: data['timezone'] as String,
  );
}

String _dateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [inviteCode] is written only when joining; Security Rules check it.
Map<String, Object?> memberToMap(Member member, {String? inviteCode}) => {
      'userId': member.userId,
      'displayName': member.displayName,
      'photoUrl': member.photoUrl,
      'selfRating': member.selfRating,
      'organizerOverride': member.organizerOverride,
      'role': member.role.name,
      'inviteCode': ?inviteCode,
    };

Member memberFromMap(Map<String, dynamic> data) => Member(
      userId: data['userId'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      selfRating: (data['selfRating'] as num).toInt(),
      organizerOverride: (data['organizerOverride'] as num?)?.toInt(),
      role: MemberRole.values.byName(data['role'] as String),
    );
```

`lib/features/groups/data/firestore_group_repository.dart`:

```dart
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
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/groups test/architecture_test.dart && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(groups): add Firestore group repository and mappers"
```

### Task 14: Firestore session repository

**Files:**
- Create: `lib/features/sessions/data/session_mapper.dart`, `lib/features/sessions/data/firestore_session_repository.dart`
- Test: `test/features/sessions/data/firestore_session_repository_test.dart`

**Interfaces:**
- Consumes: `SessionRepository` (Task 7), `guardFirestore*` (Task 13).
- Produces: `sessionToMap/sessionFromMap`, `teamToMap/teamFromMap`, `checkInToMap/checkInFromMap`; `FirestoreSessionRepository(FirebaseFirestore, {clock})`. Publishing and check-in run in transactions and return `SessionAlreadyPublished`, `SessionCancelled` or `CheckInClosed` from inside them.

- [ ] **Step 1: Write the failing tests**

`test/features/sessions/data/firestore_session_repository_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/sessions/data/firestore_session_repository.dart';
import 'package:volley_teams/features/sessions/data/session_mapper.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';

GameSession session(String id, DateTime start) => GameSession.scheduled(
      id: id, startsAt: start, teamSize: 6,
      court: const Coordinates(1, 2), radiusMeters: 150,
    );

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  late FakeFirebaseFirestore db;
  late FirestoreSessionRepository repo;
  final s1 = session('s1', DateTime.utc(2026, 9, 22, 22));
  const teams = [
    Team(index: 0, playerIds: ['a', 'b'], ratingTotal: 7),
    Team(index: 1, playerIds: ['c', 'd'], ratingTotal: 6),
  ];

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreSessionRepository(db, clock: () => now);
  });

  test('a session with teams survives a mapper round trip', () {
    final published = s1.copyWith(status: SessionStatus.teamsPublished, teams: teams, modified: true);
    expect(sessionFromMap('s1', sessionToMap(published)), published);
  });

  test('createIfAbsent creates once and never overwrites', () async {
    expect((await repo.createIfAbsent('g1', s1)).value, isTrue);
    expect((await repo.createIfAbsent('g1', s1.copyWith(teamSize: 3))).value, isFalse);
    expect((await repo.getSession('g1', 's1')).value.teamSize, 6);
  });

  test('getSession on a missing session fails with NotFound', () async {
    expect((await repo.getSession('g1', 'nope')).failure, isA<NotFound>());
  });

  test('publishTeams stores teams once; then reports published or cancelled', () async {
    await repo.createIfAbsent('g1', s1);
    expect((await repo.publishTeams('g1', 's1', teams)).isOk, isTrue);
    final stored = (await repo.getSession('g1', 's1')).value;
    expect(stored.status, SessionStatus.teamsPublished);
    expect(stored.teams, teams);
    expect((await repo.publishTeams('g1', 's1', teams)).failure, isA<SessionAlreadyPublished>());

    await repo.createIfAbsent('g1', session('s2', DateTime.utc(2026, 9, 23, 22)));
    await repo.updateSession('g1', (await repo.getSession('g1', 's2')).value.copyWith(status: SessionStatus.cancelled));
    expect((await repo.publishTeams('g1', 's2', teams)).failure, isA<SessionCancelled>());
  });

  test('checkIn writes the check-in; a closed session refuses it', () async {
    await repo.createIfAbsent('g1', s1);
    final checkIn = CheckIn(userId: 'ana', checkedInAt: now, distanceMeters: 42.5);
    expect((await repo.checkIn('g1', 's1', checkIn)).isOk, isTrue);
    expect((await repo.getCheckIns('g1', 's1')).value, [checkIn]);

    await repo.updateSession('g1', s1.copyWith(status: SessionStatus.cancelled));
    expect((await repo.checkIn('g1', 's1', CheckIn(userId: 'bruno', checkedInAt: now, distanceMeters: 1))).failure, isA<CheckInClosed>());
    expect((await repo.getCheckIns('g1', 's1')).value.map((c) => c.userId), ['ana']);
  });

  test('checkOut removes the check-in', () async {
    await repo.createIfAbsent('g1', s1);
    await repo.checkIn('g1', 's1', CheckIn(userId: 'ana', checkedInAt: now, distanceMeters: 1));
    await repo.checkOut('g1', 's1', 'ana');
    expect((await repo.getCheckIns('g1', 's1')).value, isEmpty);
  });

  test('watchUpcomingSessions hides sessions that ended more than a day ago, in start order', () async {
    await repo.createIfAbsent('g1', session('old', DateTime.utc(2026, 9, 18, 22)));
    await repo.createIfAbsent('g1', session('later', DateTime.utc(2026, 9, 29, 22)));
    await repo.createIfAbsent('g1', s1);
    expect((await repo.watchUpcomingSessions('g1').first).map((s) => s.id), ['s1', 'later']);
  });

  test('getSessionsStartingAfter and deleteSession', () async {
    await repo.createIfAbsent('g1', s1);
    await repo.createIfAbsent('g1', session('later', DateTime.utc(2026, 9, 29, 22)));
    expect((await repo.getSessionsStartingAfter('g1', DateTime.utc(2026, 9, 25))).value.map((s) => s.id), ['later']);
    await repo.deleteSession('g1', 'later');
    expect((await repo.getSession('g1', 'later')).failure, isA<NotFound>());
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/sessions/data
```

Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`lib/features/sessions/data/session_mapper.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/geo.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';

Map<String, Object?> sessionToMap(GameSession session) => {
      'startsAt': Timestamp.fromDate(session.startsAt),
      'teamSize': session.teamSize,
      'courtLat': session.court.latitude,
      'courtLng': session.court.longitude,
      'radiusMeters': session.radiusMeters,
      'checkInOpensAt': Timestamp.fromDate(session.checkInOpensAt),
      'checkInClosesAt': Timestamp.fromDate(session.checkInClosesAt),
      'status': session.status.name,
      'modified': session.modified,
      'teams': [for (final team in session.teams) teamToMap(team)],
    };

GameSession sessionFromMap(String id, Map<String, dynamic> data) => GameSession(
      id: id,
      startsAt: _utc(data['startsAt']),
      teamSize: (data['teamSize'] as num).toInt(),
      court: Coordinates(
        (data['courtLat'] as num).toDouble(),
        (data['courtLng'] as num).toDouble(),
      ),
      radiusMeters: (data['radiusMeters'] as num).toDouble(),
      checkInOpensAt: _utc(data['checkInOpensAt']),
      checkInClosesAt: _utc(data['checkInClosesAt']),
      status: SessionStatus.values.byName(data['status'] as String),
      modified: data['modified'] as bool? ?? false,
      teams: [
        for (final team in (data['teams'] as List? ?? const []))
          teamFromMap(Map<String, dynamic>.from(team as Map)),
      ],
    );

Map<String, Object?> teamToMap(Team team) => {
      'index': team.index,
      'playerIds': team.playerIds,
      'ratingTotal': team.ratingTotal,
    };

Team teamFromMap(Map<String, dynamic> data) => Team(
      index: (data['index'] as num).toInt(),
      playerIds: [for (final id in data['playerIds'] as List) id as String],
      ratingTotal: (data['ratingTotal'] as num).toInt(),
    );

Map<String, Object?> checkInToMap(CheckIn checkIn) => {
      'checkedInAt': Timestamp.fromDate(checkIn.checkedInAt),
      'distanceMeters': checkIn.distanceMeters,
    };

CheckIn checkInFromMap(String userId, Map<String, dynamic> data) => CheckIn(
      userId: userId,
      checkedInAt: _utc(data['checkedInAt']),
      distanceMeters: (data['distanceMeters'] as num).toDouble(),
    );

DateTime _utc(Object? timestamp) => (timestamp as Timestamp).toDate().toUtc();
```

`lib/features/sessions/data/firestore_session_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/firestore_guard.dart';
import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';
import '../domain/repositories/session_repository.dart';
import 'session_mapper.dart';

class FirestoreSessionRepository implements SessionRepository {
  FirestoreSessionRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  CollectionReference<Map<String, dynamic>> _sessions(String groupId) =>
      _db.collection('groups').doc(groupId).collection('sessions');

  DocumentReference<Map<String, dynamic>> _session(String groupId, String sessionId) =>
      _sessions(groupId).doc(sessionId);

  CollectionReference<Map<String, dynamic>> _checkIns(String groupId, String sessionId) =>
      _session(groupId, sessionId).collection('checkins');

  @override
  Stream<List<GameSession>> watchUpcomingSessions(String groupId) {
    final cutoff = Timestamp.fromDate(_clock().subtract(const Duration(days: 1)));
    return _sessions(groupId)
        .where('checkInClosesAt', isGreaterThan: cutoff)
        .orderBy('checkInClosesAt')
        .snapshots()
        .map((s) => [for (final d in s.docs) sessionFromMap(d.id, d.data())]);
  }

  @override
  Stream<GameSession?> watchSession(String groupId, String sessionId) =>
      _session(groupId, sessionId)
          .snapshots()
          .map((d) => d.exists ? sessionFromMap(d.id, d.data()!) : null);

  @override
  Stream<List<CheckIn>> watchCheckIns(String groupId, String sessionId) =>
      _checkIns(groupId, sessionId)
          .orderBy('checkedInAt')
          .snapshots()
          .map((s) => [for (final d in s.docs) checkInFromMap(d.id, d.data())]);

  @override
  Future<Result<GameSession>> getSession(String groupId, String sessionId) =>
      guardFirestoreResult(() async {
        final doc = await _session(groupId, sessionId).get();
        if (!doc.exists) return const Err(NotFound('session'));
        return Ok(sessionFromMap(doc.id, doc.data()!));
      });

  @override
  Future<Result<List<GameSession>>> getSessionsStartingAfter(String groupId, DateTime after) =>
      guardFirestore(() async {
        final snapshot = await _sessions(groupId)
            .where('startsAt', isGreaterThan: Timestamp.fromDate(after))
            .get();
        return [for (final d in snapshot.docs) sessionFromMap(d.id, d.data())];
      });

  @override
  Future<Result<List<CheckIn>>> getCheckIns(String groupId, String sessionId) =>
      guardFirestore(() async {
        final snapshot = await _checkIns(groupId, sessionId).get();
        return [for (final d in snapshot.docs) checkInFromMap(d.id, d.data())];
      });

  @override
  Future<Result<bool>> createIfAbsent(String groupId, GameSession session) =>
      guardFirestore(() => _db.runTransaction<bool>((tx) async {
            final ref = _session(groupId, session.id);
            if ((await tx.get(ref)).exists) return false;
            tx.set(ref, sessionToMap(session));
            return true;
          }));

  @override
  Future<Result<void>> updateSession(String groupId, GameSession session) =>
      guardFirestore(() => _session(groupId, session.id).update(sessionToMap(session)));

  @override
  Future<Result<void>> deleteSession(String groupId, String sessionId) =>
      guardFirestore(() => _session(groupId, sessionId).delete());

  @override
  Future<Result<void>> publishTeams(String groupId, String sessionId, List<Team> teams) =>
      guardFirestoreResult(() => _db.runTransaction<Result<void>>((tx) async {
            final ref = _session(groupId, sessionId);
            final doc = await tx.get(ref);
            if (!doc.exists) return const Err(NotFound('session'));
            switch (SessionStatus.values.byName(doc.data()!['status'] as String)) {
              case SessionStatus.teamsPublished:
                return const Err(SessionAlreadyPublished());
              case SessionStatus.cancelled:
                return const Err(SessionCancelled());
              case SessionStatus.scheduled:
                tx.update(ref, {
                  'status': SessionStatus.teamsPublished.name,
                  'teams': [for (final team in teams) teamToMap(team)],
                });
                return const Ok<void>(null);
            }
          }));

  @override
  Future<Result<void>> checkIn(String groupId, String sessionId, CheckIn checkIn) =>
      guardFirestoreResult(() => _db.runTransaction<Result<void>>((tx) async {
            final doc = await tx.get(_session(groupId, sessionId));
            if (!doc.exists) return const Err(NotFound('session'));
            if (doc.data()!['status'] != SessionStatus.scheduled.name) {
              return const Err(CheckInClosed());
            }
            tx.set(_checkIns(groupId, sessionId).doc(checkIn.userId), checkInToMap(checkIn));
            return const Ok<void>(null);
          }));

  @override
  Future<Result<void>> checkOut(String groupId, String sessionId, String userId) =>
      guardFirestore(() => _checkIns(groupId, sessionId).doc(userId).delete());
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/sessions test/architecture_test.dart && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(sessions): add Firestore session repository and mappers"
```

### Task 15: Firebase Auth and location implementations

**Files:**
- Create: `lib/features/auth/data/firebase_auth_repository.dart`, `lib/core/data/geolocator_location_provider.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

**Interfaces:**
- Consumes: `AuthRepository` (Task 10), `LocationProvider` (Task 2).
- Produces: `FirebaseAuthRepository(FirebaseAuth, GoogleSignIn)` (uses `google_sign_in` 7.x `authenticate()` and exchanges the ID token for a Firebase credential); `GeolocatorLocationProvider()` (checks that services are on, requests permission, times out after 15 s, and reports `isMocked`).

These wrap platform plugins, so they have no unit tests. They compile-check here and are exercised on a device in Task 19.

- [ ] **Step 1: Implement**

`lib/features/auth/data/firebase_auth_repository.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/failure.dart';
import '../../../core/result.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

/// Google sign-in through `google_sign_in` (7.x) exchanged for a Firebase
/// credential. `GoogleSignIn.instance.initialize` must have run (see main.dart).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._google);

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  @override
  Stream<AppUser?> watchUser() => _auth.authStateChanges().map(_toUser);

  @override
  Future<Result<AppUser>> signInWithGoogle() async {
    try {
      final account = await _google.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      final user = _toUser((await _auth.signInWithCredential(credential)).user);
      return user == null ? const Err(Unexpected('Sign-in returned no user')) : Ok(user);
    } on GoogleSignInException catch (e) {
      return Err(e.code == GoogleSignInExceptionCode.canceled
          ? const Unauthorized('Sign-in cancelled')
          : Unexpected(e.description ?? e.code.name));
    } on FirebaseAuthException catch (e) {
      return Err(Unexpected(e.message ?? e.code));
    }
  }

  @override
  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  AppUser? _toUser(User? user) => user == null
      ? null
      : AppUser(
          uid: user.uid,
          displayName: user.displayName ?? user.email ?? 'Player',
          photoUrl: user.photoURL,
        );
}
```

`lib/core/data/geolocator_location_provider.dart`:

```dart
import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../failure.dart';
import '../geo.dart';
import '../location_provider.dart';
import '../result.dart';

class GeolocatorLocationProvider implements LocationProvider {
  @override
  Future<Result<DevicePosition>> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const Err(Unexpected('Location services are turned off'));
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const Err(LocationPermissionDenied());
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return Ok(DevicePosition(
        coordinates: Coordinates(position.latitude, position.longitude),
        isMocked: position.isMocked,
      ));
    } on TimeoutException {
      return const Err(Unexpected('Could not get a GPS fix. Try again outdoors.'));
    }
  }
}
```

- [ ] **Step 2: Declare the location and network permissions**

In `android/app/src/main/AndroidManifest.xml`, add these as direct children of `<manifest>` (before `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

In `ios/Runner/Info.plist`, add inside the top-level `<dict>`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Volley Teams uses your location once, when you check in, to confirm you are at the court.</string>
```

- [ ] **Step 3: Verify**

```bash
flutter analyze && flutter test
```

Expected: `No issues found!` and every test passes (the architecture guard confirms `presentation` still never imports `data`).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add Firebase Auth and geolocator implementations with permissions"
```

---

## Phase 3: Presentation

### Task 16: Presentation foundation (providers, shared UI, sign-in screen)

**Files:**
- Create: `lib/core/{providers,failure_message,format}.dart`, `lib/core/widgets/{ui,rating_selector}.dart`, `lib/features/auth/presentation/{providers,sign_in_screen}.dart`, `lib/features/groups/presentation/providers.dart`, `lib/features/sessions/presentation/providers.dart`, `lib/features/teams/presentation/providers.dart`
- Test: `test/core/format_test.dart`

**Interfaces:**
- Consumes: every use case and port from Phase 1.
- Produces:
  - **Ports bound in the composition root (Task 19)**: `authRepositoryProvider`, `groupRepositoryProvider`, `sessionRepositoryProvider`, `locationServiceProvider`, `localTimezoneProvider`. Each throws `UnimplementedError` until overridden, so forgetting to bind one fails loudly. Tests override them with fakes.
  - **Ready-made providers**: a provider per use case; `authStateProvider`, `currentUserProvider`, `myGroupsProvider`, `groupProvider(groupId)`, `membersProvider(groupId)`, `upcomingSessionsProvider(groupId)`, `sessionProvider(SessionKey)`, `checkInsProvider(SessionKey)`, `generateTeamsProvider`, `publishTeamsProvider`, `clockProvider`, `randomProvider`. `SessionKey` is `({String groupId, String sessionId})`.
  - **Helpers**: `failureMessage(Failure)` (user-facing text for every failure), `formatGameTime`, `formatDate`, `weekdayName`, `showMessage`, `showFailure`, `AsyncValueView`, `SectionHeader`, `RatingSelector`.

- [ ] **Step 1: Write the failing test**

`test/core/format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/format.dart';

void main() {
  test('formats a game time as weekday, day, month and 24 h time', () {
    expect(formatGameTime(DateTime(2026, 9, 22, 19, 5)), 'Tue 22 Sep, 19:05');
  });

  test('formats a plain date', () {
    expect(formatDate(DateTime(2026, 3, 8)), '8 Mar 2026');
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/core/format_test.dart
```

Expected: FAIL to compile (`format.dart` missing).

- [ ] **Step 3: Implement the shared helpers**

`lib/core/providers.dart`:

```dart
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_provider.dart';
import 'random_codes.dart';

/// Overridden in tests with a fixed time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final randomProvider = Provider<Random>((ref) => Random.secure());

final randomCodesProvider =
    Provider<RandomCodes>((ref) => RandomCodes(ref.watch(randomProvider)));

/// Bound to the real implementation in `app/composition_root.dart`.
final locationServiceProvider = Provider<LocationProvider>(
  (ref) => throw UnimplementedError('Override locationServiceProvider in the composition root.'),
);

/// Returns the device's IANA timezone name. Bound in the composition root.
final localTimezoneProvider = Provider<Future<String> Function()>(
  (ref) => throw UnimplementedError('Override localTimezoneProvider in the composition root.'),
);
```

`lib/core/failure_message.dart`:

```dart
import 'failure.dart';

/// User-facing text for each [Failure].
String failureMessage(Failure failure) => switch (failure) {
      NotInGeofence(:final distanceMeters, :final radiusMeters) =>
        'You are ${distanceMeters.round()} m from the court. '
            'Check-in works within ${radiusMeters.round()} m.',
      MockLocationDetected() => 'Mock locations are not allowed for check-in.',
      LocationPermissionDenied() =>
        'Location permission is needed to check in. Enable it in Settings.',
      CheckInClosed() => 'Check-in is closed for this game.',
      SessionAlreadyPublished() => 'Teams were already published.',
      SessionCancelled() => 'This game was cancelled.',
      InvalidInviteCode() => 'That invite code does not exist.',
      NotEnoughPlayers(:final have, :final need) =>
        'Only $have checked in. At least $need players are needed.',
      Unauthorized(:final message) => message ?? 'You are not allowed to do that.',
      Offline() => 'You seem to be offline. Try again with a connection.',
      NotFound(:final message) => 'Not found${message == null ? '' : ': $message'}.',
      InvalidInput(:final message) => message ?? 'That input is not valid.',
      Unexpected(:final message) => message ?? 'Something went wrong.',
    };
```

`lib/core/format.dart`:

```dart
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// e.g. `Tue 22 Sep, 19:00`, in the device's local time.
String formatGameTime(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[local.weekday - 1]} ${local.day} ${_months[local.month - 1]}, '
      '${two(local.hour)}:${two(local.minute)}';
}

/// e.g. `22 Sep 2026`.
String formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String weekdayName(int weekday) => _weekdays[weekday - 1];
```

`lib/core/widgets/ui.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../failure.dart';
import '../failure_message.dart';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showFailure(BuildContext context, Failure failure) =>
    showMessage(context, failureMessage(failure));

class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({super.key, required this.value, required this.data});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Something went wrong.\n$error', textAlign: TextAlign.center),
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}
```

`lib/core/widgets/rating_selector.dart`:

```dart
import 'package:flutter/material.dart';

import '../../features/groups/domain/entities/member.dart';

/// Picks a skill rating from 1 to 5.
class RatingSelector extends StatelessWidget {
  const RatingSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (var r = minRating; r <= maxRating; r++)
            ButtonSegment(value: r, label: Text('$r')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}
```

- [ ] **Step 4: Implement the feature providers and the sign-in screen**

`lib/features/auth/presentation/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/usecases/auth_use_cases.dart';

/// Bound to the real implementation in `app/composition_root.dart`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('Override authRepositoryProvider in the composition root.'),
);

final signInWithGoogleProvider =
    Provider((ref) => SignInWithGoogle(ref.watch(authRepositoryProvider)));

final signOutProvider = Provider((ref) => SignOut(ref.watch(authRepositoryProvider)));

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => WatchAuthState(ref.watch(authRepositoryProvider))(),
);

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authStateProvider).valueOrNull);
```

`lib/features/auth/presentation/sign_in_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/ui.dart';
import 'providers.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_volleyball, size: 72),
                const SizedBox(height: 16),
                Text('Volley Teams', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text(
                  'Check in at the court. Fair teams, automatically.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  onPressed: () async {
                    final result = await ref.read(signInWithGoogleProvider)();
                    if (result.isErr && context.mounted) showFailure(context, result.failure);
                  },
                ),
              ],
            ),
          ),
        ),
      );
}
```

`lib/features/groups/presentation/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/presentation/providers.dart';
import '../domain/entities/group.dart';
import '../domain/entities/member.dart';
import '../domain/repositories/group_repository.dart';
import '../domain/usecases/create_group.dart';
import '../domain/usecases/join_group_by_code.dart';
import '../domain/usecases/organizer_guard.dart';
import '../domain/usecases/set_organizer_override.dart';
import '../domain/usecases/update_group_settings.dart';
import '../domain/usecases/update_self_rating.dart';
import '../domain/usecases/watch_groups.dart';

/// Bound to the real implementation in `app/composition_root.dart`.
final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => throw UnimplementedError('Override groupRepositoryProvider in the composition root.'),
);

final organizerGuardProvider =
    Provider((ref) => OrganizerGuard(ref.watch(groupRepositoryProvider)));

final createGroupProvider = Provider(
  (ref) => CreateGroup(ref.watch(groupRepositoryProvider), ref.watch(randomCodesProvider)),
);

final joinGroupByCodeProvider =
    Provider((ref) => JoinGroupByCode(ref.watch(groupRepositoryProvider)));

final updateSelfRatingProvider =
    Provider((ref) => UpdateSelfRating(ref.watch(groupRepositoryProvider)));

final setOrganizerOverrideProvider = Provider(
  (ref) => SetOrganizerOverride(
    ref.watch(groupRepositoryProvider),
    ref.watch(organizerGuardProvider),
  ),
);

final updateGroupSettingsProvider = Provider(
  (ref) => UpdateGroupSettings(
    ref.watch(groupRepositoryProvider),
    ref.watch(organizerGuardProvider),
  ),
);

final myGroupsProvider = StreamProvider<List<Group>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return WatchMyGroups(ref.watch(groupRepositoryProvider))(user.uid);
});

final groupProvider = StreamProvider.family<Group?, String>(
  (ref, groupId) => WatchGroup(ref.watch(groupRepositoryProvider))(groupId),
);

final membersProvider = StreamProvider.family<List<Member>, String>(
  (ref, groupId) => WatchMembers(ref.watch(groupRepositoryProvider))(groupId),
);
```

`lib/features/sessions/presentation/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../groups/presentation/providers.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/repositories/session_repository.dart';
import '../domain/services/schedule_expander.dart';
import '../domain/usecases/cancel_session.dart';
import '../domain/usecases/check_in_to_session.dart';
import '../domain/usecases/check_out_of_session.dart';
import '../domain/usecases/create_one_off_session.dart';
import '../domain/usecases/edit_session.dart';
import '../domain/usecases/ensure_upcoming_sessions.dart';
import '../domain/usecases/update_schedule.dart';
import '../domain/usecases/watch_sessions.dart';

typedef SessionKey = ({String groupId, String sessionId});

/// Bound to the real implementation in `app/composition_root.dart`.
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => throw UnimplementedError('Override sessionRepositoryProvider in the composition root.'),
);

final ensureUpcomingSessionsProvider = Provider(
  (ref) => EnsureUpcomingSessions(
    ref.watch(groupRepositoryProvider),
    ref.watch(sessionRepositoryProvider),
    const ScheduleExpander(),
    ref.watch(clockProvider),
  ),
);

final updateScheduleProvider = Provider(
  (ref) => UpdateSchedule(
    ref.watch(groupRepositoryProvider),
    ref.watch(sessionRepositoryProvider),
    ref.watch(organizerGuardProvider),
    ref.watch(ensureUpcomingSessionsProvider),
    ref.watch(clockProvider),
  ),
);

final createOneOffSessionProvider = Provider(
  (ref) => CreateOneOffSession(
    ref.watch(organizerGuardProvider),
    ref.watch(sessionRepositoryProvider),
    ref.watch(randomCodesProvider),
  ),
);

final cancelSessionProvider = Provider(
  (ref) => CancelSession(ref.watch(organizerGuardProvider), ref.watch(sessionRepositoryProvider)),
);

final editSessionProvider = Provider(
  (ref) => EditSession(ref.watch(organizerGuardProvider), ref.watch(sessionRepositoryProvider)),
);

final checkInProvider = Provider(
  (ref) => CheckInToSession(
    ref.watch(sessionRepositoryProvider),
    ref.watch(locationServiceProvider),
    ref.watch(clockProvider),
  ),
);

final checkOutProvider =
    Provider((ref) => CheckOutOfSession(ref.watch(sessionRepositoryProvider)));

final removeCheckInProvider = Provider(
  (ref) => RemoveCheckIn(ref.watch(organizerGuardProvider), ref.watch(sessionRepositoryProvider)),
);

final upcomingSessionsProvider = StreamProvider.family<List<GameSession>, String>(
  (ref, groupId) => WatchUpcomingSessions(ref.watch(sessionRepositoryProvider))(groupId),
);

final sessionProvider = StreamProvider.family<GameSession?, SessionKey>(
  (ref, key) => WatchSession(ref.watch(sessionRepositoryProvider))(key.groupId, key.sessionId),
);

final checkInsProvider = StreamProvider.family<List<CheckIn>, SessionKey>(
  (ref, key) => WatchCheckIns(ref.watch(sessionRepositoryProvider))(key.groupId, key.sessionId),
);
```

`lib/features/teams/presentation/providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../groups/presentation/providers.dart';
import '../../sessions/presentation/providers.dart';
import '../domain/services/team_balancer.dart';
import '../domain/usecases/generate_teams.dart';
import '../domain/usecases/publish_teams.dart';

final generateTeamsProvider = Provider(
  (ref) => GenerateTeams(
    ref.watch(organizerGuardProvider),
    ref.watch(groupRepositoryProvider),
    ref.watch(sessionRepositoryProvider),
    const TeamBalancer(),
    ref.watch(randomProvider),
  ),
);

final publishTeamsProvider = Provider(
  (ref) => PublishTeams(ref.watch(organizerGuardProvider), ref.watch(sessionRepositoryProvider)),
);
```

- [ ] **Step 5: Run tests and the analyzer**

```bash
flutter test && flutter analyze
```

Expected: PASS, and `No issues found!`. (The architecture guard now also checks that `presentation` never imports `data`.)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(presentation): add providers, shared UI helpers and sign-in screen"
```

### Task 17: Session screen (check-in, generate, publish)

**Files:**
- Create: `lib/features/teams/presentation/widgets/teams_view.dart`, `lib/features/sessions/presentation/session_screen.dart`
- Test: `test/support/app_harness.dart`, `test/features/sessions/presentation/session_screen_test.dart`

**Interfaces:**
- Consumes: Task 16 providers; `FakeGroupRepository`, `FakeSessionRepository`, `FakeLocationProvider`, `FakeAuthRepository` (Tasks 6 to 10).
- Produces: `SessionScreen({groupId, sessionId})`; `TeamsView({teams, names, highlightUserId})`; test support `Harness({user, now})` (fakes wired into a `ProviderScope`, with `seed()` and `app(home)`), `boss` (the organizer user) and `useTallScreen(tester)`.

Behaviour the tests pin down: a player can check in inside the radius and is told the distance outside it; the button is hidden before the window opens; the organizer's preview is not persisted until they publish; too few check-ins shows a clear message; cancelling asks for confirmation.

- [ ] **Step 1: Write the test harness and the failing tests**

`test/support/app_harness.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/providers.dart';
import 'package:volley_teams/features/auth/domain/entities/app_user.dart';
import 'package:volley_teams/features/auth/presentation/providers.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/member.dart';
import 'package:volley_teams/features/groups/presentation/providers.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/presentation/providers.dart';

import 'fake_auth_repository.dart';
import 'fake_group_repository.dart';
import 'fake_location_provider.dart';
import 'fake_session_repository.dart';

const boss = AppUser(uid: 'boss', displayName: 'Boss');

/// Fakes for every port, wired into a [ProviderScope].
class Harness {
  Harness({AppUser? user = FakeAuthRepository.defaultUser, DateTime? now})
      : auth = FakeAuthRepository(signedIn: user),
        now = now ?? DateTime.utc(2026, 9, 22, 22);

  final FakeAuthRepository auth;
  final groups = FakeGroupRepository();
  final sessions = FakeSessionRepository();
  final location = FakeLocationProvider();
  DateTime now;

  List<Override> get overrides => [
        authRepositoryProvider.overrideWithValue(auth),
        groupRepositoryProvider.overrideWithValue(groups),
        sessionRepositoryProvider.overrideWithValue(sessions),
        locationServiceProvider.overrideWithValue(location),
        localTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
        clockProvider.overrideWithValue(() => now),
        randomProvider.overrideWithValue(Random(1)),
      ];

  /// Group `g1` (organizer "boss") with players ana, p1..p5 rated 1..5, and one
  /// scheduled session `s1` that starts at [now] with teams of [teamSize].
  void seed({int teamSize = 3, Group? group}) {
    groups.groups['g1'] = group ??
        const Group(id: 'g1', name: 'Sunday Vôlei', organizerId: 'boss', inviteCode: 'ABCD2345', court: Coordinates(0, 0));
    groups.members['g1'] = {
      'boss': const Member(userId: 'boss', displayName: 'Boss', selfRating: 3, role: MemberRole.organizer),
      'ana': const Member(userId: 'ana', displayName: 'Ana', selfRating: 3, role: MemberRole.player),
      for (var i = 1; i <= 5; i++)
        'p$i': Member(userId: 'p$i', displayName: 'Player $i', selfRating: i, role: MemberRole.player),
    };
    sessions.sessions['g1'] = {
      's1': GameSession.scheduled(
        id: 's1', startsAt: now, teamSize: teamSize,
        court: const Coordinates(0, 0), radiusMeters: 150,
      ),
    };
  }

  Widget app(Widget home) => ProviderScope(overrides: overrides, child: MaterialApp(home: home));
}

/// Gives widgets room, so nothing needs scrolling in tests.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
```

`test/features/sessions/presentation/session_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/core/location_provider.dart';
import 'package:volley_teams/features/sessions/domain/entities/check_in.dart';
import 'package:volley_teams/features/sessions/domain/entities/game_session.dart';
import 'package:volley_teams/features/sessions/presentation/session_screen.dart';

import '../../../support/app_harness.dart';

Future<void> pumpSession(WidgetTester tester, Harness h) async {
  useTallScreen(tester);
  await tester.pumpWidget(h.app(const SessionScreen(groupId: 'g1', sessionId: 's1')));
  await tester.pumpAndSettle();
}

void checkInPlayers(Harness h, Iterable<String> ids) {
  h.sessions.checkIns['g1/s1'] = {
    for (final id in ids) id: CheckIn(userId: id, checkedInAt: h.now, distanceMeters: 5),
  };
}

void main() {
  group('player check-in', () {
    testWidgets('inside the geofence the player is checked in', (tester) async {
      final h = Harness()..seed();
      h.location.position = const DevicePosition(coordinates: Coordinates(0.0005, 0)); // ~55 m
      await pumpSession(tester, h);

      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();

      expect(find.text("You're checked in"), findsOneWidget);
      expect(find.text('Check out'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1']!.keys, ['ana']);
    });

    testWidgets('outside the geofence shows the distance and stays unchecked', (tester) async {
      final h = Harness()..seed();
      h.location.position = const DevicePosition(coordinates: Coordinates(0.002, 0)); // ~222 m
      await pumpSession(tester, h);

      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('from the court'), findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1'] ?? {}, isEmpty);
    });

    testWidgets('before the window opens there is no check-in button', (tester) async {
      final h = Harness()..seed();
      h.now = h.now.subtract(const Duration(hours: 2));
      await pumpSession(tester, h);

      expect(find.text('Check in'), findsNothing);
      expect(find.textContaining('Check-in opens at'), findsOneWidget);
    });

    testWidgets('a checked-in player can check out', (tester) async {
      final h = Harness()..seed();
      checkInPlayers(h, ['ana']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Check out'));
      await tester.pumpAndSettle();

      expect(find.text('Check in'), findsOneWidget);
      expect(h.sessions.checkIns['g1/s1']!, isEmpty);
    });
  });

  group('organizer', () {
    testWidgets('generates a preview, then publishes it', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1', 'p2', 'p3', 'p4', 'p5']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-0')), findsOneWidget);
      expect(find.byKey(const Key('team-1')), findsOneWidget);
      expect(find.text('Publish teams'), findsOneWidget);
      // A preview is not persisted.
      expect(h.sessions.sessions['g1']!['s1']!.status, SessionStatus.scheduled);

      await tester.tap(find.text('Publish teams'));
      await tester.pumpAndSettle();

      final stored = h.sessions.sessions['g1']!['s1']!;
      expect(stored.status, SessionStatus.teamsPublished);
      expect(stored.teams, hasLength(2));
      expect(find.text('Publish teams'), findsNothing);
      expect(find.text('Teams'), findsOneWidget);
      expect(find.byKey(const Key('team-0')), findsOneWidget);
    });

    testWidgets('with too few check-ins the organizer is told why', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1']);
      await pumpSession(tester, h);

      await tester.tap(find.text('Generate teams'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only 2 checked in'), findsOneWidget);
      expect(find.byKey(const Key('team-0')), findsNothing);
    });

    testWidgets('the organizer removes a check-in; a player has no such button', (tester) async {
      final h = Harness(user: boss)..seed();
      checkInPlayers(h, ['ana', 'p1']);
      await pumpSession(tester, h);

      await tester.tap(find.descendant(of: find.byKey(const Key('checkin-p1')), matching: find.byType(IconButton)));
      await tester.pumpAndSettle();
      expect(h.sessions.checkIns['g1/s1']!.keys, ['ana']);

      final player = Harness()..seed();
      checkInPlayers(player, ['p1']);
      await pumpSession(tester, player);
      expect(find.byTooltip('Remove check-in'), findsNothing);
      expect(find.text('Generate teams'), findsNothing);
    });

    testWidgets('cancelling asks for confirmation and marks the game cancelled', (tester) async {
      final h = Harness(user: boss)..seed();
      await pumpSession(tester, h);

      await tester.tap(find.text('Cancel game'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel game'));
      await tester.pumpAndSettle();

      expect(h.sessions.sessions['g1']!['s1']!.status, SessionStatus.cancelled);
      expect(find.text('This game was cancelled'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/sessions/presentation
```

Expected: FAIL to compile (`session_screen.dart` missing).

- [ ] **Step 3: Implement**

`lib/features/teams/presentation/widgets/teams_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../sessions/domain/entities/team.dart';

class TeamsView extends StatelessWidget {
  const TeamsView({
    super.key,
    required this.teams,
    required this.names,
    this.highlightUserId,
  });

  final List<Team> teams;

  /// userId -> display name.
  final Map<String, String> names;
  final String? highlightUserId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final team in teams)
          Card(
            key: Key('team-${team.index}'),
            color: team.playerIds.contains(highlightUserId) ? scheme.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Team ${team.index + 1}', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Text('avg ${team.averageRating.toStringAsFixed(1)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final id in team.playerIds)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(names[id] ?? 'Unknown player'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

`lib/features/sessions/presentation/session_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../../groups/presentation/providers.dart';
import '../../teams/presentation/providers.dart';
import '../../teams/presentation/widgets/teams_view.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';
import 'providers.dart';

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.groupId, required this.sessionId});

  final String groupId;
  final String sessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  List<Team>? _preview;
  int _previewPlayerCount = 0;
  bool _busy = false;

  SessionKey get _key => (groupId: widget.groupId, sessionId: widget.sessionId);

  /// Runs [action] with the busy flag set and shows any failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(String userId) => _run(() async {
        final result = await ref.read(checkInProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          userId: userId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _checkOut(String userId) => _run(() async {
        final result = await ref.read(checkOutProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          userId: userId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _removeCheckIn(String actingUserId, String targetUserId) => _run(() async {
        final result = await ref.read(removeCheckInProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: actingUserId,
          targetUserId: targetUserId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _generate(String userId, int checkedInCount) => _run(() async {
        final result = await ref.read(generateTeamsProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: userId,
        );
        if (!mounted) return;
        if (result.isErr) return showFailure(context, result.failure);
        setState(() {
          _preview = result.value;
          _previewPlayerCount = checkedInCount;
        });
      });

  Future<void> _publish(String userId) => _run(() async {
        final teams = _preview;
        if (teams == null) return;
        final result = await ref.read(publishTeamsProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: userId,
          teams: teams,
        );
        if (!mounted) return;
        if (result.isErr) return showFailure(context, result.failure);
        setState(() => _preview = null);
      });

  Future<void> _cancel(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this game?'),
        content: const Text('Players will see it as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel game')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final result = await ref.read(cancelSessionProvider)(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        actingUserId: userId,
      );
      if (result.isErr && mounted) showFailure(context, result.failure);
    });
  }

  Future<void> _edit(String userId, GameSession session) async {
    final edit = await showDialog<({int teamSize, DateTime startsAt})>(
      context: context,
      builder: (_) => _EditGameDialog(session: session),
    );
    if (edit == null) return;
    await _run(() async {
      final result = await ref.read(editSessionProvider)(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        actingUserId: userId,
        teamSize: edit.teamSize,
        startsAt: edit.startsAt,
      );
      if (!mounted) return;
      if (result.isErr) return showFailure(context, result.failure);
      setState(() => _preview = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final sessionAsync = ref.watch(sessionProvider(_key));
    final checkIns = ref.watch(checkInsProvider(_key)).valueOrNull ?? const <CheckIn>[];
    final members = ref.watch(membersProvider(widget.groupId)).valueOrNull ?? const [];
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final now = ref.watch(clockProvider)();
    if (user == null) return const SizedBox.shrink();

    final names = {for (final m in members) m.userId: m.displayName};
    final isOrganizer = group?.organizerId == user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Game')),
      body: AsyncValueView(
        value: sessionAsync,
        data: (session) {
          if (session == null) return const Center(child: Text('This game no longer exists.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(formatGameTime(session.startsAt), style: Theme.of(context).textTheme.headlineSmall),
              Text('${session.teamSize} players per team'),
              const SizedBox(height: 16),
              switch (session.status) {
                SessionStatus.cancelled => const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy),
                      title: Text('This game was cancelled'),
                    ),
                  ),
                SessionStatus.teamsPublished => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Teams', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TeamsView(teams: session.teams, names: names, highlightUserId: user.uid),
                    ],
                  ),
                SessionStatus.scheduled => _scheduledBody(
                    session, user.uid, isOrganizer, checkIns, names, now),
              },
            ],
          );
        },
      ),
    );
  }

  Widget _scheduledBody(
    GameSession session,
    String userId,
    bool isOrganizer,
    List<CheckIn> checkIns,
    Map<String, String> names,
    DateTime now,
  ) {
    final checkedIn = checkIns.any((c) => c.userId == userId);
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: checkedIn
                ? Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      const Expanded(child: Text("You're checked in")),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _checkOut(userId),
                        child: const Text('Check out'),
                      ),
                    ],
                  )
                : session.isCheckInOpen(now)
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.place_outlined),
                          label: const Text('Check in'),
                          onPressed: _busy ? null : () => _checkIn(userId),
                        ),
                      )
                    : Text(now.isBefore(session.checkInOpensAt)
                        ? 'Check-in opens at ${formatGameTime(session.checkInOpensAt)}'
                        : 'Check-in is closed'),
          ),
        ),
        SectionHeader('Checked in (${checkIns.length})'),
        if (checkIns.isEmpty) const Text('Nobody has checked in yet.'),
        for (final checkIn in checkIns)
          ListTile(
            key: Key('checkin-${checkIn.userId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(names[checkIn.userId] ?? 'Unknown player'),
            trailing: isOrganizer
                ? IconButton(
                    tooltip: 'Remove check-in',
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => _removeCheckIn(userId, checkIn.userId),
                  )
                : null,
          ),
        if (isOrganizer) ...[
          const SectionHeader('Organizer'),
          if (preview == null)
            FilledButton.icon(
              icon: const Icon(Icons.shuffle),
              label: const Text('Generate teams'),
              onPressed: _busy ? null : () => _generate(userId, checkIns.length),
            )
          else ...[
            if (_previewPlayerCount != checkIns.length)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Check-ins changed since this draw. Reshuffle to include everyone.'),
              ),
            TeamsView(teams: preview, names: names),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _generate(userId, checkIns.length),
                  child: const Text('Reshuffle'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _publish(userId),
                  child: const Text('Publish teams'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: _busy ? null : () => _edit(userId, session), child: const Text('Edit game')),
              TextButton(onPressed: _busy ? null : () => _cancel(userId), child: const Text('Cancel game')),
            ],
          ),
        ],
      ],
    );
  }
}

class _EditGameDialog extends StatefulWidget {
  const _EditGameDialog({required this.session});

  final GameSession session;

  @override
  State<_EditGameDialog> createState() => _EditGameDialogState();
}

class _EditGameDialogState extends State<_EditGameDialog> {
  late int _teamSize = widget.session.teamSize;
  late DateTime _startsAt = widget.session.startsAt.toLocal();

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_startsAt));
    if (time == null) return;
    setState(() => _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit this game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Players per team')),
                IconButton(
                  tooltip: 'Fewer',
                  icon: const Icon(Icons.remove),
                  onPressed: _teamSize > 2 ? () => setState(() => _teamSize--) : null,
                ),
                Text('$_teamSize'),
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _teamSize++),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start'),
              subtitle: Text(formatGameTime(_startsAt)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickTime,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (teamSize: _teamSize, startsAt: _startsAt.toUtc())),
            child: const Text('Save'),
          ),
        ],
      );
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/features/sessions/presentation && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(sessions): add session screen with check-in and team generation"
```

### Task 18: Group screens (list, detail, settings, schedule)

**Files:**
- Create: `lib/features/groups/presentation/{groups_screen,group_detail_screen,group_settings_screen,schedule_screen}.dart`, `lib/features/groups/presentation/widgets/{rating_dialog,member_list,session_list}.dart`
- Test: `test/features/groups/presentation/group_detail_screen_test.dart`

**Interfaces:**
- Consumes: Task 16 providers; `Harness` (Task 17).
- Produces: `GroupsScreen()`, `GroupDetailScreen({groupId})`, `GroupSettingsScreen({groupId})`, `ScheduleScreen({groupId})`, `showRatingDialog(...)`, `MemberList`, `SessionList`. The route paths they are wired to in Task 19 are `/`, `/groups/:groupId`, `/groups/:groupId/settings`, `/groups/:groupId/schedule`.

Behaviour the tests pin down: opening a group as its organizer creates the scheduled games (waiting for the signed-in user to load first), organizer-only actions are hidden from players, and a member can edit their own rating while the organizer can override anyone's.

- [ ] **Step 1: Write the failing tests**

`test/features/groups/presentation/group_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:volley_teams/core/geo.dart';
import 'package:volley_teams/features/groups/domain/entities/group.dart';
import 'package:volley_teams/features/groups/domain/entities/schedule.dart';
import 'package:volley_teams/features/groups/presentation/group_detail_screen.dart';

import '../../../support/app_harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('opening a group as organizer creates the scheduled games', (tester) async {
    useTallScreen(tester);
    // 2026-03-01 12:00 UTC is a Sunday morning in New York.
    final h = Harness(user: boss, now: DateTime.utc(2026, 3, 1, 12))
      ..seed(
        group: Group(
          id: 'g1', name: 'Sunday Vôlei', organizerId: 'boss', inviteCode: 'ABCD2345',
          court: const Coordinates(0, 0),
          schedule: const Schedule(
            weekdays: {DateTime.sunday},
            startTime: LocalTime(19, 0),
            timezone: 'America/New_York',
          ),
        ),
      );
    h.sessions.sessions['g1'] = {};

    await tester.pumpWidget(h.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();

    expect(h.sessions.sessions['g1']!.keys,
        ['2026-03-01T19:00', '2026-03-08T19:00', '2026-03-15T19:00', '2026-03-22T19:00']);
    expect(find.byKey(const Key('session-2026-03-08T19:00')), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
  });

  testWidgets('the organizer sees organizer actions; a plain player does not', (tester) async {
    useTallScreen(tester);
    final organizer = Harness(user: boss)..seed();
    await tester.pumpWidget(organizer.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('One-off game'), findsOneWidget);

    final player = Harness()..seed();
    await tester.pumpWidget(player.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.byKey(const Key('member-p1')), findsOneWidget);
  });

  testWidgets('a player can change their own rating; the organizer can override anyone', (tester) async {
    useTallScreen(tester);
    final h = Harness(user: boss)..seed();
    await tester.pumpWidget(h.app(const GroupDetailScreen(groupId: 'g1')));
    await tester.pumpAndSettle();

    // Organizer taps Player 1 (self-rated 1) and sets an override of 4.
    await tester.tap(find.byKey(const Key('member-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('4')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(h.groups.members['g1']!['p1']!.organizerOverride, 4);
    expect(h.groups.members['g1']!['p1']!.selfRating, 1);
    expect(find.textContaining('organizer set 4'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/features/groups/presentation
```

Expected: FAIL to compile (`group_detail_screen.dart` missing).

- [ ] **Step 3: Implement the widgets and screens**

`lib/features/groups/presentation/widgets/rating_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/widgets/rating_selector.dart';

/// Result: null when dismissed, `(rating: n)` on save, `(rating: null)` when
/// the override is cleared.
Future<({int? rating})?> showRatingDialog(
  BuildContext context, {
  required String title,
  required int initial,
  bool allowClear = false,
}) =>
    showDialog<({int? rating})>(
      context: context,
      builder: (_) => _RatingDialog(title: title, initial: initial, allowClear: allowClear),
    );

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({required this.title, required this.initial, required this.allowClear});

  final String title;
  final int initial;
  final bool allowClear;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  late int _rating = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: RatingSelector(value: _rating, onChanged: (r) => setState(() => _rating = r)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (widget.allowClear)
            TextButton(
              onPressed: () => Navigator.pop(context, (rating: null)),
              child: const Text('Clear override'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (rating: _rating)),
            child: const Text('Save'),
          ),
        ],
      );
}
```

`lib/features/groups/presentation/widgets/member_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/ui.dart';
import '../../../auth/presentation/providers.dart';
import '../../domain/entities/member.dart';
import '../providers.dart';
import 'rating_dialog.dart';

class MemberList extends ConsumerWidget {
  const MemberList({super.key, required this.groupId, required this.isOrganizer});

  final String groupId;
  final bool isOrganizer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    return AsyncValueView(
      value: ref.watch(membersProvider(groupId)),
      data: (members) => Column(
        children: [
          for (final member in members)
            ListTile(
              key: Key('member-${member.userId}'),
              leading: CircleAvatar(child: Text(member.displayName.characters.first.toUpperCase())),
              title: Text(member.isOrganizer ? '${member.displayName} (organizer)' : member.displayName),
              subtitle: Text(
                member.organizerOverride == null
                    ? 'Self-rated ${member.selfRating}'
                    : 'Self-rated ${member.selfRating}, organizer set ${member.organizerOverride}',
              ),
              trailing: Chip(label: Text('${member.effectiveRating}')),
              onTap: member.userId == me?.uid
                  ? () => _editSelf(context, ref, member)
                  : isOrganizer
                      ? () => _editOverride(context, ref, member)
                      : null,
            ),
        ],
      ),
    );
  }

  Future<void> _editSelf(BuildContext context, WidgetRef ref, Member member) async {
    final choice = await showRatingDialog(
      context,
      title: 'Your skill level',
      initial: member.selfRating,
    );
    final rating = choice?.rating;
    if (rating == null) return;
    final result = await ref.read(updateSelfRatingProvider)(
      groupId: groupId,
      userId: member.userId,
      rating: rating,
    );
    if (result.isErr && context.mounted) showFailure(context, result.failure);
  }

  Future<void> _editOverride(BuildContext context, WidgetRef ref, Member member) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final choice = await showRatingDialog(
      context,
      title: 'Rating for ${member.displayName}',
      initial: member.effectiveRating,
      allowClear: member.organizerOverride != null,
    );
    if (choice == null) return;
    final result = await ref.read(setOrganizerOverrideProvider)(
      groupId: groupId,
      actingUserId: me.uid,
      targetUserId: member.userId,
      rating: choice.rating,
    );
    if (result.isErr && context.mounted) showFailure(context, result.failure);
  }
}
```

`lib/features/groups/presentation/widgets/session_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format.dart';
import '../../../../core/widgets/ui.dart';
import '../../../sessions/domain/entities/game_session.dart';
import '../../../sessions/presentation/providers.dart';

class SessionList extends ConsumerWidget {
  const SessionList({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncValueView(
        value: ref.watch(upcomingSessionsProvider(groupId)),
        data: (sessions) => sessions.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No upcoming games yet.'),
              )
            : Column(
                children: [
                  for (final session in sessions)
                    ListTile(
                      key: Key('session-${session.id}'),
                      leading: const Icon(Icons.event_outlined),
                      title: Text(formatGameTime(session.startsAt)),
                      subtitle: Text(_subtitle(session)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/groups/$groupId/sessions/${session.id}'),
                    ),
                ],
              ),
      );

  String _subtitle(GameSession session) => switch (session.status) {
        SessionStatus.scheduled => '${session.teamSize} players per team',
        SessionStatus.teamsPublished => 'Teams published',
        SessionStatus.cancelled => 'Cancelled',
      };
}
```

`lib/features/groups/presentation/groups_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/rating_selector.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../domain/entities/member.dart';
import 'providers.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My groups'),
        actions: [
          IconButton(
            tooltip: 'Join with a code',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => _join(context, ref),
          ),
          IconButton(
            tooltip: 'Create a group',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context, ref),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(signOutProvider)(),
          ),
        ],
      ),
      body: AsyncValueView(
        value: groups,
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'You are not in a group yet.\nCreate one, or join with an invite code.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                children: [
                  for (final group in list)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(group.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/groups/${group.id}'),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    final input = await showDialog<({String name, int rating})>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (input == null || user == null || !context.mounted) return;

    final position = await ref.read(locationServiceProvider).currentPosition();
    if (position.isErr) {
      if (context.mounted) showFailure(context, position.failure);
      return;
    }
    final result = await ref.read(createGroupProvider)(
      name: input.name,
      court: position.value.coordinates,
      organizer: Member(
        userId: user.uid,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        selfRating: input.rating,
        role: MemberRole.organizer,
      ),
    );
    if (!context.mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    context.push('/groups/${result.value.id}');
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    final input = await showDialog<({String code, int rating})>(
      context: context,
      builder: (_) => const _JoinGroupDialog(),
    );
    if (input == null || user == null || !context.mounted) return;

    final result = await ref.read(joinGroupByCodeProvider)(
      code: input.code,
      member: Member(
        userId: user.uid,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        selfRating: input.rating,
        role: MemberRole.player,
      ),
    );
    if (!context.mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    context.push('/groups/${result.value.id}');
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _name = TextEditingController();
  int _rating = 3;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create a group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 16),
            const Text('Your skill level (1 to 5)'),
            const SizedBox(height: 8),
            RatingSelector(value: _rating, onChanged: (r) => setState(() => _rating = r)),
            const SizedBox(height: 16),
            const Text(
              'The court location is set to where you are right now. '
              'You can change it later in the group settings.',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (name: _name.text, rating: _rating)),
            child: const Text('Create'),
          ),
        ],
      );
}

class _JoinGroupDialog extends StatefulWidget {
  const _JoinGroupDialog();

  @override
  State<_JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<_JoinGroupDialog> {
  final _code = TextEditingController();
  int _rating = 3;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Join a group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Invite code'),
            ),
            const SizedBox(height: 16),
            const Text('Your skill level (1 to 5)'),
            const SizedBox(height: 8),
            RatingSelector(value: _rating, onChanged: (r) => setState(() => _rating = r)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (code: _code.text, rating: _rating)),
            child: const Text('Join'),
          ),
        ],
      );
}
```

`lib/features/groups/presentation/group_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../../sessions/presentation/providers.dart';
import 'providers.dart';
import 'widgets/member_list.dart';
import 'widgets/session_list.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  bool _ensured = false;

  @override
  void initState() {
    super.initState();
    // Recurring games are created by the organizer's device (no server jobs).
    // Wait for the signed-in user, which may not have loaded yet.
    ref.listenManual(currentUserProvider, (_, user) {
      if (user != null && !_ensured) {
        _ensured = true;
        _ensureSessions(user.uid);
      }
    }, fireImmediately: true);
  }

  Future<void> _ensureSessions(String userId) async {
    final result = await ref.read(ensureUpcomingSessionsProvider)(
      groupId: widget.groupId,
      userId: userId,
    );
    if (result.isErr && mounted) showFailure(context, result.failure);
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: Text(groupAsync.valueOrNull?.name ?? 'Group')),
      body: AsyncValueView(
        value: groupAsync,
        data: (group) {
          if (group == null) return const Center(child: Text('This group no longer exists.'));
          final isOrganizer = group.organizerId == user?.uid;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: Text(group.inviteCode, style: const TextStyle(letterSpacing: 2)),
                  subtitle: const Text('Invite code'),
                  trailing: IconButton(
                    tooltip: 'Copy invite code',
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: group.inviteCode));
                      if (context.mounted) showMessage(context, 'Invite code copied');
                    },
                  ),
                ),
              ),
              if (isOrganizer)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.repeat),
                      label: const Text('Schedule'),
                      onPressed: () => context.push('/groups/${group.id}/schedule'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Settings'),
                      onPressed: () => context.push('/groups/${group.id}/settings'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('One-off game'),
                      onPressed: () => _addOneOff(context, group.id, user!.uid),
                    ),
                  ],
                ),
              const SectionHeader('Upcoming games'),
              SessionList(groupId: group.id),
              const SectionHeader('Members'),
              MemberList(groupId: group.id, isOrganizer: isOrganizer),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addOneOff(BuildContext context, String groupId, String userId) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 0));
    if (time == null) return;
    final local = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final result = await ref.read(createOneOffSessionProvider)(
      groupId: groupId,
      actingUserId: userId,
      startsAt: local.toUtc(),
    );
    if (result.isErr && context.mounted) showFailure(context, result.failure);
  }
}
```

`lib/features/groups/presentation/group_settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../domain/entities/group.dart';
import 'providers.dart';

class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Group settings')),
        body: AsyncValueView(
          value: ref.watch(groupProvider(groupId)),
          data: (group) => group == null
              ? const Center(child: Text('This group no longer exists.'))
              : _SettingsForm(group: group),
        ),
      );
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.group});

  final Group group;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _radius = TextEditingController(text: widget.group.radiusMeters.round().toString());
  late final _teamSize = TextEditingController(text: widget.group.defaultTeamSize.toString());
  late Coordinates _court = widget.group.court;

  @override
  void dispose() {
    _radius.dispose();
    _teamSize.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final position = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    if (position.isErr) return showFailure(context, position.failure);
    setState(() => _court = position.value.coordinates);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    final radius = double.tryParse(_radius.text.trim());
    final teamSize = int.tryParse(_teamSize.text.trim());
    if (user == null || radius == null || teamSize == null) {
      return showMessage(context, 'Enter a whole number for the radius and the team size.');
    }
    final result = await ref.read(updateGroupSettingsProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      court: _court,
      radiusMeters: radius,
      defaultTeamSize: teamSize,
    );
    if (!mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    showMessage(context, 'Settings saved. New games use them; existing games keep theirs.');
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Court location'),
            subtitle: Text('${_court.latitude.toStringAsFixed(5)}, ${_court.longitude.toStringAsFixed(5)}'),
            trailing: OutlinedButton(
              onPressed: _useCurrentLocation,
              child: const Text('Use my location'),
            ),
          ),
          TextField(
            controller: _radius,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Check-in radius (metres)'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _teamSize,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Default players per team'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
```

`lib/features/groups/presentation/schedule_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../../sessions/presentation/providers.dart';
import '../domain/entities/group.dart';
import '../domain/entities/schedule.dart';
import 'providers.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Weekly schedule')),
        body: AsyncValueView(
          value: ref.watch(groupProvider(groupId)),
          data: (group) => group == null
              ? const Center(child: Text('This group no longer exists.'))
              : _ScheduleForm(group: group),
        ),
      );
}

class _ScheduleForm extends ConsumerStatefulWidget {
  const _ScheduleForm({required this.group});

  final Group group;

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  late Set<int> _weekdays = {...?widget.group.schedule?.weekdays};
  late TimeOfDay _time = TimeOfDay(
    hour: widget.group.schedule?.startTime.hour ?? 19,
    minute: widget.group.schedule?.startTime.minute ?? 0,
  );
  late DateTime? _endDate = widget.group.schedule?.endDate;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_weekdays.isEmpty) return showMessage(context, 'Pick at least one weekday.');
    final timezone =
        widget.group.schedule?.timezone ?? await ref.read(localTimezoneProvider)();
    final result = await ref.read(updateScheduleProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      schedule: Schedule(
        weekdays: _weekdays,
        startTime: LocalTime(_time.hour, _time.minute),
        endDate: _endDate,
        timezone: timezone,
      ),
    );
    if (!mounted) return;
    result.isErr
        ? showFailure(context, result.failure)
        : showMessage(context, 'Schedule saved. ${result.value} new games created.');
  }

  Future<void> _remove() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final result = await ref.read(updateScheduleProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      schedule: null,
    );
    if (!mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    setState(() => _weekdays = {});
    showMessage(context, 'Recurring games removed.');
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.group.schedule;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Games repeat every week on:'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              FilterChip(
                label: Text(weekdayName(day)),
                selected: _weekdays.contains(day),
                onSelected: (on) => setState(() => on ? _weekdays.add(day) : _weekdays.remove(day)),
              ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start time'),
          subtitle: Text(_time.format(context)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: _time);
            if (picked != null) setState(() => _time = picked);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeat until (optional)'),
          subtitle: Text(_endDate == null ? 'No end date' : formatDate(_endDate!)),
          trailing: _endDate == null
              ? const Icon(Icons.event)
              : IconButton(
                  tooltip: 'Clear end date',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _endDate = null),
                ),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _endDate ?? now.add(const Duration(days: 90)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 730)),
            );
            if (picked != null) setState(() => _endDate = picked);
          },
        ),
        if (existing != null) Text('Times are in ${existing.timezone}.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save schedule')),
        if (existing != null)
          TextButton(onPressed: _remove, child: const Text('Remove recurring games')),
      ],
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test && flutter analyze
```

Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(groups): add group list, detail, settings and schedule screens"
```

### Task 19: Wire the app, verify end to end, document

**Files:**
- Create: `lib/app/{router,app,composition_root}.dart`, `README.md`
- Modify: `lib/main.dart` (replace the Task 11 smoke test)
- Test: `test/app/app_flow_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: the runnable app. `routerProvider` (auth-gated `go_router`: `/splash` while auth loads, `/sign-in` when signed out, `/` when signed in), `VolleyApp`, `buildOverrides()` (the only place that binds ports to Firebase, geolocator and `flutter_timezone`), and the real `main()`.

- [ ] **Step 1: Write the failing tests**

`test/app/app_flow_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/app/app.dart';

import '../support/app_harness.dart';

void main() {
  testWidgets('signed-out users see the sign-in screen and land on My groups after signing in', (tester) async {
    final h = Harness(user: null)..seed();
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const VolleyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('My groups'), findsNothing);

    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(find.text('My groups'), findsOneWidget);
    expect(find.text('Sunday Vôlei'), findsOneWidget); // ana is a member of g1
  });

  testWidgets('a signed-in user starts on My groups and can sign out', (tester) async {
    final h = Harness()..seed();
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const VolleyApp()));
    await tester.pumpAndSettle();
    expect(find.text('My groups'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure**

```bash
flutter test test/app
```

Expected: FAIL to compile (`app/app.dart` missing).

- [ ] **Step 3: Implement the router, app shell and composition root**

`lib/app/router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/providers.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/groups/presentation/group_detail_screen.dart';
import '../features/groups/presentation/group_settings_screen.dart';
import '../features/groups/presentation/groups_screen.dart';
import '../features/groups/presentation/schedule_screen.dart';
import '../features/sessions/presentation/session_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the signed-in user changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final location = state.matchedLocation;
      if (auth.isLoading) return location == '/splash' ? null : '/splash';
      if (auth.valueOrNull == null) return location == '/sign-in' ? null : '/sign-in';
      return (location == '/sign-in' || location == '/splash') ? '/' : null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const GroupsScreen(),
        routes: [
          GoRoute(
            path: 'groups/:groupId',
            builder: (_, state) => GroupDetailScreen(groupId: state.pathParameters['groupId']!),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, state) =>
                    GroupSettingsScreen(groupId: state.pathParameters['groupId']!),
              ),
              GoRoute(
                path: 'schedule',
                builder: (_, state) => ScheduleScreen(groupId: state.pathParameters['groupId']!),
              ),
              GoRoute(
                path: 'sessions/:sessionId',
                builder: (_, state) => SessionScreen(
                  groupId: state.pathParameters['groupId']!,
                  sessionId: state.pathParameters['sessionId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
```

`lib/app/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class VolleyApp extends ConsumerWidget {
  const VolleyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Volley Teams',
        routerConfig: ref.watch(routerProvider),
        theme: ThemeData(colorSchemeSeed: Colors.orange, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.orange,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
      );
}
```

`lib/app/composition_root.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/data/geolocator_location_provider.dart';
import '../core/providers.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/presentation/providers.dart';
import '../features/groups/data/firestore_group_repository.dart';
import '../features/groups/presentation/providers.dart';
import '../features/sessions/data/firestore_session_repository.dart';
import '../features/sessions/presentation/providers.dart';

/// The only place that binds domain interfaces to Firebase and device
/// implementations. Tests override the same providers with fakes.
List<Override> buildOverrides() {
  final firestore = FirebaseFirestore.instance;
  return [
    authRepositoryProvider.overrideWithValue(
      FirebaseAuthRepository(FirebaseAuth.instance, GoogleSignIn.instance),
    ),
    groupRepositoryProvider.overrideWithValue(FirestoreGroupRepository(firestore)),
    sessionRepositoryProvider.overrideWithValue(FirestoreSessionRepository(firestore)),
    locationServiceProvider.overrideWithValue(GeolocatorLocationProvider()),
    localTimezoneProvider.overrideWithValue(FlutterTimezone.getLocalTimezone),
  ];
}
```

- [ ] **Step 4: Replace the smoke-test entry point**

`lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'app/app.dart';
import 'app/composition_root.dart';
import 'firebase_config.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize(
    serverClientId: googleServerClientId.isEmpty ? null : googleServerClientId,
  );
  runApp(ProviderScope(overrides: buildOverrides(), child: const VolleyApp()));
}
```

- [ ] **Step 5: Run the whole suite, the analyzer and the rules tests**

```bash
flutter analyze && flutter test
(cd rules-tests && npm test)
```

Expected: `No issues found!`; every Flutter test passes; the rules suite reports `pass 22`.

- [ ] **Step 6: Run the app on a real device (owner)**

Use physical devices, because the emulator's fake GPS is reported as mocked on Android. Pass the Web client ID from Task 11:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_CLIENT_ID>.apps.googleusercontent.com
```

Work through this checklist with two Google accounts on two devices (A is the organizer, B is a player) and tick each item:

- [ ] Sign in with Google on Android; sign in on iOS.
- [ ] A creates a group while standing at the court (location prompt appears, the group opens, the invite code is shown).
- [ ] B joins with the code and a different rating; B appears in A's member list.
- [ ] A sets a weekly schedule for today's weekday a few minutes ahead; a game appears for A and for B.
- [ ] B checks in inside the radius and appears in both devices' "Checked in" lists.
- [ ] Set the radius to 10 m in the group settings, walk 30 m away, try again: B is told the distance and stays unchecked.
- [ ] Deny the location permission: B gets the permission message. Turn on airplane mode: B gets the offline message.
- [ ] On Android, enable a mock-location app in developer options: check-in is refused.
- [ ] A taps Generate, then Reshuffle, then Publish; B sees the teams appear live with their own team highlighted; the top-rated players are on different teams.
- [ ] Publishing again is not offered; A can still cancel a different game; A's rating override changes the next draw.

- [ ] **Step 7: Write the README**

Create `README.md`:

````markdown
# Volley Teams

Players check in at the court; the organizer generates balanced volleyball teams. Flutter + Firebase (Google sign-in, Firestore), Clean Architecture.

Design: `docs/superpowers/specs/2026-09-20-volleyball-team-manager-design.md`.
Plan: `docs/superpowers/plans/2026-09-20-volleyball-team-manager.md`.

## Setup

1. Create a Firebase project with Google sign-in and Firestore enabled, then run `flutterfire configure --project=<id> --platforms=android,ios`.
2. Add your Android debug SHA-1 fingerprint in the Firebase console, and the iOS reversed client id to `ios/Runner/Info.plist`.
3. Deploy rules and index: `firebase deploy --only firestore:rules,firestore:indexes --project <id>`.

## Run

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

## Test

```bash
flutter analyze && flutter test        # domain, data, widget and architecture tests
(cd rules-tests && npm install && npm test)   # Security Rules against the Firestore emulator
```

## Architecture

`lib/features/<feature>/{domain,data,presentation}`. Domain is pure Dart; `presentation -> domain <- data` is enforced by `test/architecture_test.dart`. Ports are bound to Firebase in `lib/app/composition_root.dart`; tests bind fakes.
````

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: wire the app (router, composition root, main) and add README"
```

---

## Spec coverage

| Spec section | Where it is implemented |
|---|---|
| 3 Architecture | Task 1 (guard test), Tasks 2 to 19 (layers), composition root in Task 19 |
| 4 Domain model | Task 3 |
| 5 Firestore layout and recurrence | Tasks 5, 7 (expansion, ensure, update schedule), 12 (rules, index), 13 to 14 (repositories) |
| 6 Team balancing, generate and publish | Tasks 4, 9; UI in Task 17 |
| 7 Auth, joining, check-in | Tasks 6, 8, 10; data in Tasks 13, 15; UI in Tasks 16 to 18 |
| 8 Security Rules | Task 12 |
| 9 Screens | Tasks 16 to 19 |
| 10 Error handling | Task 2 (`Failure`), Task 16 (`failureMessage`), transactions in Tasks 13 to 14. The offline banner is not built (Clarifications, item 10) |
| 11 Testing | Every task is test-first; rules tests in Task 12; manual checklist in Task 19 |
| 12 Out of scope | Not built: late arrivals, multiple organizers, push notifications, stats, other recurrences, Cloud Functions, web/desktop |
| 13 Prerequisites | Task 11 |
