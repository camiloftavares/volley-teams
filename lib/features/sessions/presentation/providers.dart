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
