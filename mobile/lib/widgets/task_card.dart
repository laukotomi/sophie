import 'package:flutter/material.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/add_task_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/utils/note_colors.dart';
import 'package:sophie/widgets/note_chip.dart';

class TaskCard extends StatefulWidget {
  final Task task;
  final BackendClient client;
  final VoidCallback onChanged;
  final List<AppUser> allUsers;
  final String currentUserId;

  const TaskCard({
    super.key,
    required this.task,
    required this.client,
    required this.onChanged,
    required this.allUsers,
    required this.currentUserId,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _loading = false;

  Future<void> _toggleDone() async {
    setState(() => _loading = true);
    final markingDone = widget.task.doneAt == null;
    try {
      await widget.client.setTaskDone(
        taskId: widget.task.id,
        done: markingDone,
      );
      if (markingDone) {
        await AlertNotifications.cancelForTask(widget.task.id);
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTaskScreen(
          users: widget.allUsers,
          currentUserId: widget.currentUserId,
          client: widget.client,
          existingTask: widget.task,
        ),
      ),
    );
    if (changed == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = widget.task.doneAt != null;

    return Card(
      color: widget.task.color != null ? hexToColor(widget.task.color!) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GestureDetector(
                        onTap: _toggleDone,
                        child: Icon(
                          done
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: done ? theme.colorScheme.primary : null,
                        ),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.task.text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done
                          ? theme.colorScheme.onSurface.withAlpha(120)
                          : null,
                    ),
                  ),
                ),
                if (widget.task.isOwner)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit task',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openEdit,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.task.isOwner)
                        NoteChip(
                          icon: Icons.check_circle_outline,
                          label: 'Owner',
                          color: theme.colorScheme.primaryContainer,
                          textColor: theme.colorScheme.onPrimaryContainer,
                        )
                      else
                        NoteChip(
                          icon: Icons.person_outline,
                          label: 'Collaborator',
                          color: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                      ...widget.task.collaborators.map(
                        (c) => NoteChip(
                          icon: Icons.person,
                          label: c.name,
                          color: theme.colorScheme.tertiaryContainer,
                          textColor: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      if (widget.task.rrule != null &&
                          widget.task.rrule!.isNotEmpty)
                        NoteChip(
                          icon: Icons.repeat,
                          label: 'Recurring',
                          color: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                      if (widget.task.alerts.isNotEmpty)
                        NoteChip(
                          icon: Icons.notifications_outlined,
                          label:
                              '${widget.task.alerts.length} alert${widget.task.alerts.length == 1 ? '' : 's'}',
                          color: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDue(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _isDueOverdue()
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDue() {
    if (widget.task.dueAt == null) {
      return _formatDate(widget.task.createdAt);
    }
    final d = widget.task.dueAt!;
    return 'Due ${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  }

  bool _isDueOverdue() {
    if (widget.task.dueAt == null || widget.task.doneAt != null) return false;
    return widget.task.dueAt!.isBefore(DateTime.now());
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
