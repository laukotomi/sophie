import 'package:flutter/material.dart';

class NoteChip extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final Color textColor;

  const NoteChip({
    super.key,
    required this.icon,
    this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(label!, style: TextStyle(fontSize: 12, color: textColor)),
          ],
        ],
      ),
    );
  }
}
