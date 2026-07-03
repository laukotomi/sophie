import 'package:flutter/material.dart';

/// Shows a confirmation dialog asking whether to discard unsaved changes.
/// Returns [true] if the user chose to discard, [false] or null otherwise.
Future<bool?> showDiscardDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Discard changes?'),
      content: const Text('Your changes will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
}
