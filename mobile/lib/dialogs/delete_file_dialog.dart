import 'package:flutter/material.dart';

/// Shows a confirmation dialog asking whether to delete [fileName].
/// Returns [true] if the user confirmed deletion, [false] or null otherwise.
Future<bool?> showDeleteFileDialog(BuildContext context, String fileName) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete file'),
      content: Text(
        'Are you sure you want to delete "$fileName"? This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
