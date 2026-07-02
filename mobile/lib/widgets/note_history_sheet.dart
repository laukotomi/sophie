import 'package:flutter/material.dart';
import 'package:sophie/models/note_history_entry.dart';

class NoteHistorySheet extends StatelessWidget {
  final List<NoteHistoryEntry> history;
  final void Function(String text) onLoad;

  const NoteHistorySheet({
    super.key,
    required this.history,
    required this.onLoad,
  });

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Version history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              itemCount: history.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final entry = history[index];
                final preview = entry.text.trim().replaceAll('\n', ' ');
                final truncated = preview.length > 100
                    ? '${preview.substring(0, 100)}…'
                    : preview;
                return ListTile(
                  title: Text(_formatDate(entry.createdAt)),
                  subtitle: Text(
                    truncated,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Load this version?'),
                        content: const Text(
                          'Your current text will be replaced. Save afterwards to restore it.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(d).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(d).pop(true),
                            child: const Text('Load'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      onLoad(entry.text);
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
