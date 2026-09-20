import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../../sessions/presentation/providers.dart';
import '../domain/entities/group.dart';
import '../domain/entities/schedule.dart';
import 'providers.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Weekly schedule')),
        body: AsyncValueView(
          value: ref.watch(groupProvider(groupId)),
          data: (group) => group == null
              ? const Center(child: Text('This group no longer exists.'))
              : _ScheduleForm(group: group),
        ),
      );
}

class _ScheduleForm extends ConsumerStatefulWidget {
  const _ScheduleForm({required this.group});

  final Group group;

  @override
  ConsumerState<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends ConsumerState<_ScheduleForm> {
  late Set<int> _weekdays = {...?widget.group.schedule?.weekdays};
  late TimeOfDay _time = TimeOfDay(
    hour: widget.group.schedule?.startTime.hour ?? 19,
    minute: widget.group.schedule?.startTime.minute ?? 0,
  );
  late DateTime? _endDate = widget.group.schedule?.endDate;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_weekdays.isEmpty) return showMessage(context, 'Pick at least one weekday.');
    final timezone =
        widget.group.schedule?.timezone ?? await ref.read(localTimezoneProvider)();
    final result = await ref.read(updateScheduleProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      schedule: Schedule(
        weekdays: _weekdays,
        startTime: LocalTime(_time.hour, _time.minute),
        endDate: _endDate,
        timezone: timezone,
      ),
    );
    if (!mounted) return;
    result.isErr
        ? showFailure(context, result.failure)
        : showMessage(context, 'Schedule saved. ${result.value} new games created.');
  }

  Future<void> _remove() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final result = await ref.read(updateScheduleProvider)(
      groupId: widget.group.id,
      actingUserId: user.uid,
      schedule: null,
    );
    if (!mounted) return;
    if (result.isErr) return showFailure(context, result.failure);
    setState(() => _weekdays = {});
    showMessage(context, 'Recurring games removed.');
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.group.schedule;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Games repeat every week on:'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (var day = DateTime.monday; day <= DateTime.sunday; day++)
              FilterChip(
                label: Text(weekdayName(day)),
                selected: _weekdays.contains(day),
                onSelected: (on) => setState(() => on ? _weekdays.add(day) : _weekdays.remove(day)),
              ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start time'),
          subtitle: Text(_time.format(context)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: _time);
            if (picked != null) setState(() => _time = picked);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeat until (optional)'),
          subtitle: Text(_endDate == null ? 'No end date' : formatDate(_endDate!)),
          trailing: _endDate == null
              ? const Icon(Icons.event)
              : IconButton(
                  tooltip: 'Clear end date',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _endDate = null),
                ),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _endDate ?? now.add(const Duration(days: 90)),
              firstDate: now,
              lastDate: now.add(const Duration(days: 730)),
            );
            if (picked != null) setState(() => _endDate = picked);
          },
        ),
        if (existing != null) Text('Times are in ${existing.timezone}.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Save schedule')),
        if (existing != null)
          TextButton(onPressed: _remove, child: const Text('Remove recurring games')),
      ],
    );
  }
}
