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
