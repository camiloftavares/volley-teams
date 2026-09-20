import 'package:flutter/material.dart';

import '../../../../core/widgets/rating_selector.dart';

/// Result: null when dismissed, `(rating: n)` on save, `(rating: null)` when
/// the override is cleared.
Future<({int? rating})?> showRatingDialog(
  BuildContext context, {
  required String title,
  required int initial,
  bool allowClear = false,
}) =>
    showDialog<({int? rating})>(
      context: context,
      builder: (_) => _RatingDialog(title: title, initial: initial, allowClear: allowClear),
    );

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({required this.title, required this.initial, required this.allowClear});

  final String title;
  final int initial;
  final bool allowClear;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  late int _rating = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: RatingSelector(value: _rating, onChanged: (r) => setState(() => _rating = r)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (widget.allowClear)
            TextButton(
              onPressed: () => Navigator.pop(context, (rating: null)),
              child: const Text('Clear override'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (rating: _rating)),
            child: const Text('Save'),
          ),
        ],
      );
}
