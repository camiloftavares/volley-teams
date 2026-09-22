import 'package:flutter/material.dart';

import '../../../../core/rating.dart';
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
                      Text('avg ${averageTierLabel(team.averageRating)}'),
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
