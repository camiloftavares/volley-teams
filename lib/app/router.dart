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
