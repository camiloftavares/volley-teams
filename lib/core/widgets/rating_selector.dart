import 'package:flutter/material.dart';

import '../rating.dart';

/// Picks a skill tier: A, B, or C (stored as an int 1-3).
class RatingSelector extends StatelessWidget {
  const RatingSelector({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (var r = maxRating; r >= minRating; r--)
            ButtonSegment(value: r, label: Text(ratingTierLabel(r))),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}
