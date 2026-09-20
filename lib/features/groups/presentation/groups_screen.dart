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
