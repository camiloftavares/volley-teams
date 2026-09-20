import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/ui.dart';
import '../../../auth/presentation/providers.dart';
import '../../domain/entities/member.dart';
import '../providers.dart';
import 'rating_dialog.dart';

class MemberList extends ConsumerWidget {
  const MemberList({super.key, required this.groupId, required this.isOrganizer});

  final String groupId;
  final bool isOrganizer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    return AsyncValueView(
      value: ref.watch(membersProvider(groupId)),
      data: (members) => Column(
        children: [
          for (final member in members)
            ListTile(
              key: Key('member-${member.userId}'),
              leading: CircleAvatar(child: Text(member.displayName.characters.first.toUpperCase())),
              title: Text(member.isOrganizer ? '${member.displayName} (organizer)' : member.displayName),
              subtitle: Text(
                member.organizerOverride == null
                    ? 'Self-rated ${member.selfRating}'
                    : 'Self-rated ${member.selfRating}, organizer set ${member.organizerOverride}',
              ),
              trailing: Chip(label: Text('${member.effectiveRating}')),
              onTap: member.userId == me?.uid
                  ? () => _editSelf(context, ref, member)
                  : isOrganizer
                      ? () => _editOverride(context, ref, member)
                      : null,
            ),
        ],
      ),
    );
  }

  Future<void> _editSelf(BuildContext context, WidgetRef ref, Member member) async {
    final choice = await showRatingDialog(
      context,
      title: 'Your skill level',
      initial: member.selfRating,
    );
    final rating = choice?.rating;
    if (rating == null) return;
    final result = await ref.read(updateSelfRatingProvider)(
      groupId: groupId,
      userId: member.userId,
      rating: rating,
    );
    if (result.isErr && context.mounted) showFailure(context, result.failure);
  }

  Future<void> _editOverride(BuildContext context, WidgetRef ref, Member member) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final choice = await showRatingDialog(
      context,
      title: 'Rating for ${member.displayName}',
      initial: member.effectiveRating,
      allowClear: member.organizerOverride != null,
    );
    if (choice == null) return;
    final result = await ref.read(setOrganizerOverrideProvider)(
      groupId: groupId,
      actingUserId: me.uid,
      targetUserId: member.userId,
      rating: choice.rating,
    );
    if (result.isErr && context.mounted) showFailure(context, result.failure);
  }
}
