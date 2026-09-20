import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/ui.dart';
import '../../auth/presentation/providers.dart';
import '../../groups/presentation/providers.dart';
import '../../teams/presentation/providers.dart';
import '../../teams/presentation/widgets/teams_view.dart';
import '../domain/entities/check_in.dart';
import '../domain/entities/game_session.dart';
import '../domain/entities/team.dart';
import 'providers.dart';

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.groupId, required this.sessionId});

  final String groupId;
  final String sessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  List<Team>? _preview;
  Set<String> _previewCheckInIds = const {};
  bool _busy = false;

  SessionKey get _key => (groupId: widget.groupId, sessionId: widget.sessionId);

  /// Runs [action] with the busy flag set and shows any failure.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(String userId) => _run(() async {
        final result = await ref.read(checkInProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          userId: userId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _checkOut(String userId) => _run(() async {
        final result = await ref.read(checkOutProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          userId: userId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _removeCheckIn(String actingUserId, String targetUserId) => _run(() async {
        final result = await ref.read(removeCheckInProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: actingUserId,
          targetUserId: targetUserId,
        );
        if (result.isErr && mounted) showFailure(context, result.failure);
      });

  Future<void> _generate(String userId, Set<String> checkedInIds) => _run(() async {
        final result = await ref.read(generateTeamsProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: userId,
        );
        if (!mounted) return;
        if (result.isErr) return showFailure(context, result.failure);
        setState(() {
          _preview = result.value;
          _previewCheckInIds = checkedInIds;
        });
      });

  Future<void> _publish(String userId) => _run(() async {
        final teams = _preview;
        if (teams == null) return;
        final result = await ref.read(publishTeamsProvider)(
          groupId: widget.groupId,
          sessionId: widget.sessionId,
          actingUserId: userId,
          teams: teams,
        );
        if (!mounted) return;
        if (result.isErr) return showFailure(context, result.failure);
        setState(() => _preview = null);
      });

  Future<void> _cancel(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this game?'),
        content: const Text('Players will see it as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel game')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final result = await ref.read(cancelSessionProvider)(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        actingUserId: userId,
      );
      if (result.isErr && mounted) showFailure(context, result.failure);
    });
  }

  Future<void> _edit(String userId, GameSession session) async {
    final edit = await showDialog<({int teamSize, DateTime startsAt})>(
      context: context,
      builder: (_) => _EditGameDialog(session: session),
    );
    if (edit == null) return;
    await _run(() async {
      final result = await ref.read(editSessionProvider)(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        actingUserId: userId,
        teamSize: edit.teamSize,
        startsAt: edit.startsAt,
      );
      if (!mounted) return;
      if (result.isErr) return showFailure(context, result.failure);
      setState(() => _preview = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final sessionAsync = ref.watch(sessionProvider(_key));
    final checkIns = ref.watch(checkInsProvider(_key)).valueOrNull ?? const <CheckIn>[];
    final members = ref.watch(membersProvider(widget.groupId)).valueOrNull ?? const [];
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final now = ref.watch(clockProvider)();
    if (user == null) return const SizedBox.shrink();

    final names = {for (final m in members) m.userId: m.displayName};
    final isOrganizer = group?.organizerId == user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Game')),
      body: AsyncValueView(
        value: sessionAsync,
        data: (session) {
          if (session == null) return const Center(child: Text('This game no longer exists.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(formatGameTime(session.startsAt), style: Theme.of(context).textTheme.headlineSmall),
              Text('${session.teamSize} players per team'),
              const SizedBox(height: 16),
              switch (session.status) {
                SessionStatus.cancelled => const Card(
                    child: ListTile(
                      leading: Icon(Icons.event_busy),
                      title: Text('This game was cancelled'),
                    ),
                  ),
                SessionStatus.teamsPublished => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Teams', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TeamsView(teams: session.teams, names: names, highlightUserId: user.uid),
                    ],
                  ),
                SessionStatus.scheduled => _scheduledBody(
                    session, user.uid, isOrganizer, checkIns, names, now),
              },
            ],
          );
        },
      ),
    );
  }

  Widget _scheduledBody(
    GameSession session,
    String userId,
    bool isOrganizer,
    List<CheckIn> checkIns,
    Map<String, String> names,
    DateTime now,
  ) {
    final checkedIn = checkIns.any((c) => c.userId == userId);
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: checkedIn
                ? Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 8),
                      const Expanded(child: Text("You're checked in")),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _checkOut(userId),
                        child: const Text('Check out'),
                      ),
                    ],
                  )
                : session.isCheckInOpen(now)
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.place_outlined),
                          label: const Text('Check in'),
                          onPressed: _busy ? null : () => _checkIn(userId),
                        ),
                      )
                    : Text(now.isBefore(session.checkInOpensAt)
                        ? 'Check-in opens at ${formatGameTime(session.checkInOpensAt)}'
                        : 'Check-in is closed'),
          ),
        ),
        SectionHeader('Checked in (${checkIns.length})'),
        if (checkIns.isEmpty) const Text('Nobody has checked in yet.'),
        for (final checkIn in checkIns)
          ListTile(
            key: Key('checkin-${checkIn.userId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(names[checkIn.userId] ?? 'Unknown player'),
            trailing: isOrganizer
                ? IconButton(
                    tooltip: 'Remove check-in',
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => _removeCheckIn(userId, checkIn.userId),
                  )
                : null,
          ),
        if (isOrganizer) ...[
          const SectionHeader('Organizer'),
          if (preview == null)
            FilledButton.icon(
              icon: const Icon(Icons.shuffle),
              label: const Text('Generate teams'),
              onPressed: _busy ? null : () => _generate(userId, {for (final c in checkIns) c.userId}),
            )
          else ...[
            if (!setEquals(_previewCheckInIds, {for (final c in checkIns) c.userId}))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Check-ins changed since this draw. Reshuffle to include everyone.'),
              ),
            TeamsView(teams: preview, names: names),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _generate(userId, {for (final c in checkIns) c.userId}),
                  child: const Text('Reshuffle'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _publish(userId),
                  child: const Text('Publish teams'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: _busy ? null : () => _edit(userId, session), child: const Text('Edit game')),
              TextButton(onPressed: _busy ? null : () => _cancel(userId), child: const Text('Cancel game')),
            ],
          ),
        ],
      ],
    );
  }
}

class _EditGameDialog extends StatefulWidget {
  const _EditGameDialog({required this.session});

  final GameSession session;

  @override
  State<_EditGameDialog> createState() => _EditGameDialogState();
}

class _EditGameDialogState extends State<_EditGameDialog> {
  late int _teamSize = widget.session.teamSize;
  late DateTime _startsAt = widget.session.startsAt.toLocal();

  Future<void> _pickTime() async {
    final firstDate = DateTime.now().subtract(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      // A game that began more than a day ago must not push initialDate before firstDate.
      initialDate: _startsAt.isBefore(firstDate) ? firstDate : _startsAt,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_startsAt));
    if (time == null) return;
    setState(() => _startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit this game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Players per team')),
                IconButton(
                  tooltip: 'Fewer',
                  icon: const Icon(Icons.remove),
                  onPressed: _teamSize > 2 ? () => setState(() => _teamSize--) : null,
                ),
                Text('$_teamSize'),
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _teamSize++),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start'),
              subtitle: Text(formatGameTime(_startsAt)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickTime,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (teamSize: _teamSize, startsAt: _startsAt.toUtc())),
            child: const Text('Save'),
          ),
        ],
      );
}
