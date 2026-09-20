import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../domain/entities/group.dart';
import 'providers.dart';

class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Group settings')),
        body: AsyncValueView(
          value: ref.watch(groupProvider(groupId)),
          data: (group) => group == null
              ? const Center(child: Text('This group no longer exists.'))
              : _SettingsForm(group: group),
        ),
      );
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.group});

  final Group group;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final _radius = TextEditingController(text: widget.group.radiusMeters.round().toString());
  late final _teamSize = TextEditingController(text: widget.group.defaultTeamSize.toString());
  late Coordinates _court = widget.group.court;

  @override
  void dispose() {
    _radius.dispose();
    _teamSize.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final position = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    if (position.isErr) return showFailure(context, position.failure);
    setState(() => _court = position.value.coordinates);
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    final radius = double.tryParse(_radius.text.trim());
    final teamSize = int.tryParse(_teamSize.text.trim());
    if (user == null || radius == null || teamSize == null) {
      return showMessage(context, 'Enter a whole number for the radius and the team size.');
    }
    final result = await ref.read(updateGroupSettingsProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      court: _court,
      radiusMeters: radius,
      defaultTeamSize: teamSize,
    );
    if (!mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    showMessage(context, 'Settings saved. New games use them; existing games keep theirs.');
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Court location'),
            subtitle: Text('${_court.latitude.toStringAsFixed(5)}, ${_court.longitude.toStringAsFixed(5)}'),
            trailing: OutlinedButton(
              onPressed: _useCurrentLocation,
              child: const Text('Use my location'),
            ),
          ),
          TextField(
            controller: _radius,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Check-in radius (metres)'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _teamSize,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Default players per team'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
