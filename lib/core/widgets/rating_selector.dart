import 'package:flutter/material.dart';

import '../../features/groups/domain/entities/member.dart';

/// Picks a skill rating from 1 to 5.
class RatingSelector extends StatelessWidget {
  const RatingSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (var r = minRating; r <= maxRating; r++)
            ButtonSegment(value: r, label: Text('$r')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}
