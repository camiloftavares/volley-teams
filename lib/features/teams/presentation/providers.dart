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
