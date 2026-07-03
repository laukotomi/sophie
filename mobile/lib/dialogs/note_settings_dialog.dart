import 'package:flutter/material.dart';

class NoteSettingsDialog extends StatefulWidget {
  final int? initialPosition;
  final String? initialColor;
  final bool initialDontFold;
  final bool initialTodoList;
  final List<String?> palette;
  final Color Function(String) contrastColor;
  final void Function(
    int? position,
    String? color,
    bool dontFold,
    bool todoList,
  )
  onApply;

  const NoteSettingsDialog({
    super.key,
    required this.initialPosition,
    required this.initialColor,
    this.initialDontFold = false,
    this.initialTodoList = false,
    required this.palette,
    required this.contrastColor,
    required this.onApply,
  });

  @override
  State<NoteSettingsDialog> createState() => _NoteSettingsDialogState();
}

class _NoteSettingsDialogState extends State<NoteSettingsDialog> {
  late final TextEditingController _controller;
  late String? _selectedColor;
  late bool _dontFold;
  late bool _todoList;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialPosition?.toString() ?? '',
    );
    _selectedColor = widget.initialColor;
    _dontFold = widget.initialDontFold;
    _todoList = widget.initialTodoList;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note settings'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fixed position',
                hintText: 'Leave empty for automatic',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Background color'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.palette.map((hex) {
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: hex == null
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : Color(
                              int.parse('FF${hex.substring(1)}', radix: 16),
                            ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: hex == null
                                ? Theme.of(context).colorScheme.onSurface
                                : widget.contrastColor(hex),
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Don't fold"),
              subtitle: const Text('Always show the full note'),
              value: _dontFold,
              onChanged: (v) => setState(() => _dontFold = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Todo list'),
              value: _todoList,
              onChanged: (v) => setState(() => _todoList = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final raw = _controller.text.trim();
            final position = raw.isEmpty ? null : int.tryParse(raw);
            Navigator.of(context).pop();
            widget.onApply(position, _selectedColor, _dontFold, _todoList);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
