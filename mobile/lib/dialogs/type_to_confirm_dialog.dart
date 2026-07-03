import 'package:flutter/material.dart';

/// A dialog that requires the user to type a specific word before the confirm
/// button becomes enabled. Useful for irreversible destructive actions.
///
/// Returns `true` when confirmed, `false` / `null` otherwise.
class TypeToConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmWord;
  final String confirmLabel;

  const TypeToConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmWord = 'yes',
    this.confirmLabel = 'Confirm',
  });

  @override
  State<TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<TypeToConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _controller.text.trim().toLowerCase() == widget.confirmWord.toLowerCase();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.confirmWord,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
