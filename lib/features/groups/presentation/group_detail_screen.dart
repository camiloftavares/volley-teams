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
