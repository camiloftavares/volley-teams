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
