import 'package:flutter/material.dart';
import 'package:sophie/utils/note_colors.dart';

class TaskSettingsDialog extends StatefulWidget {
  final String? initialColor;
  final void Function(String? color) onApply;

  const TaskSettingsDialog({
    super.key,
    required this.initialColor,
    required this.onApply,
  });

  @override
  State<TaskSettingsDialog> createState() => _TaskSettingsDialogState();
}

class _TaskSettingsDialogState extends State<TaskSettingsDialog> {
  late String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Task settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Background color'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kNotePalette.map((hex) {
              final isSelected = _selectedColor == hex;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = hex),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hex == null
                        ? Theme.of(context).colorScheme.surfaceContainerLow
                        : hexToColor(hex),
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
                              : noteContrastColor(hex),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onApply(_selectedColor);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
