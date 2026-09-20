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
