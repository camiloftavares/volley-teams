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
flutter run --dart-define-from-file=dart_defines.json
```

## Test

```bash
flutter analyze && flutter test        # domain, data, widget and architecture tests
(cd rules-tests && npm install && npm test)   # Security Rules against the Firestore emulator
```

## Architecture

`lib/features/<feature>/{domain,data,presentation}`. Domain is pure Dart; `presentation -> domain <- data` is enforced by `test/architecture_test.dart`. Ports are bound to Firebase in `lib/app/composition_root.dart`; tests bind fakes.

## Security notes

- The backend is client-only, so the geofence is enforced on the device. The Security Rules cannot verify GPS; they only check membership, the check-in time window and that a user writes their own check-in.
- Mock-location detection relies on `geolocator`'s `Position.isMocked`. On Android it reports mock providers. On iOS 15 and later `geolocator_apple` fills it from CoreLocation's `isSimulatedBySoftware`, which catches software-simulated locations but not hardware or jailbreak-based spoofing; below iOS 15 it is always `false`. Neither platform can detect a determined spoofer, so the geofence also relies on social mitigations: the organizer can remove any check-in, and check-ins are visible to the whole group.
- `checkedInAt` and `distanceMeters` are written by the client and are not validated by the rules. A determined member with a modified client can fake a check-in; the organizer's "remove check-in" is the real control.
