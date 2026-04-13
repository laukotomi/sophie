import 'package:flutter/material.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/widgets/task_settings_dialog.dart';

/// An alert is stored either as an absolute datetime or as a duration before dueAt.
/// When the user picks a time and _dueAt is set, we compute the difference and
/// store it as [timeBefore]. Otherwise we store [alertAt].
class _Alert {
  final DateTime? alertAt;
  final Duration? timeBefore;

  const _Alert.absolute(DateTime this.alertAt) : timeBefore = null;
  const _Alert.relative(Duration this.timeBefore) : alertAt = null;
}

class AddTaskScreen extends StatefulWidget {
  final List<AppUser> users;
  final String currentUserId;
  final BackendClient client;
  // When non-null the screen is in edit mode
  final Task? existingTask;

  const AddTaskScreen({
    super.key,
    required this.users,
    required this.currentUserId,
    required this.client,
    this.existingTask,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;
  bool _saving = false;
  bool _deleting = false;
  late DateTime? _dueAt;
  late String _rrule;
  late final List<_Alert> _alerts;
  late final List<AppUser> _collaborators;
  String? _color;

  bool get _isEditing => widget.existingTask != null;

  bool get _hasChanges {
    final t = widget.existingTask;
    if (t == null) {
      return _textController.text.trim().isNotEmpty ||
          _dueAt != null ||
          _rrule.isNotEmpty ||
          _alerts.isNotEmpty ||
          _collaborators.isNotEmpty;
    }
    final originalCollabIds = t.collaborators.map((c) => c.id).toSet();
    final currentCollabIds = _collaborators.map((u) => u.id).toSet();
    return _textController.text.trim() != t.text.trim() ||
        _dueAt != t.dueAt ||
        _rrule != (t.rrule ?? '') ||
        _color != t.color ||
        originalCollabIds.length != currentCollabIds.length ||
        !originalCollabIds.containsAll(currentCollabIds) ||
        _alerts.length != t.alerts.length;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _textController = TextEditingController(text: t?.text ?? '');
    _dueAt = t?.dueAt;
    _rrule = t?.rrule ?? '';
    _color = t?.color;
    // Pre-populate alerts from existing task
    _alerts = t == null
        ? []
        : t.alerts.map((a) {
            if (a.alertAt != null) return _Alert.absolute(a.alertAt!);
            // Parse 'HH:MM:SS' timeBefore into a Duration
            final parts = (a.timeBefore ?? '0:0:0').split(':');
            final h = int.tryParse(parts[0]) ?? 0;
            final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
            return _Alert.relative(Duration(hours: h, minutes: m));
          }).toList();
    // Pre-populate collaborators from existing task
    _collaborators = t == null
        ? []
        : t.collaborators
              .map((c) => widget.users.where((u) => u.id == c.id).firstOrNull)
              .whereType<AppUser>()
              .toList();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _dueAt != null
          ? TimeOfDay.fromDateTime(_dueAt!)
          : TimeOfDay.now(),
    );
    if (!mounted) return;

    setState(() {
      _dueAt = time == null
          ? DateTime(date.year, date.month, date.day)
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _addAlert() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (_dueAt != null) {
      final diff = _dueAt!.difference(picked);
      if (diff.isNegative || diff == Duration.zero) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alert must be before the due date.')),
          );
        }
        return;
      }
      setState(() => _alerts.add(_Alert.relative(diff)));
    } else {
      setState(() => _alerts.add(_Alert.absolute(picked)));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String taskId;
      if (_isEditing) {
        taskId = widget.existingTask!.id;
        await widget.client.updateTask(
          taskId: taskId,
          text: _textController.text.trim(),
          rrule: _rrule.isNotEmpty ? _rrule : null,
          dueAt: _dueAt,
          color: _color,
          collaboratorIds: _collaborators.map((u) => u.id).toList(),
          alerts: _alerts
              .map((a) => (alertAt: a.alertAt, timeBefore: a.timeBefore))
              .toList(),
        );
      } else {
        taskId = await widget.client.createTask(
          text: _textController.text.trim(),
          rrule: _rrule.isNotEmpty ? _rrule : null,
          dueAt: _dueAt,
          color: _color,
          collaboratorIds: _collaborators.map((u) => u.id).toList(),
          alerts: _alerts
              .map((a) => (alertAt: a.alertAt, timeBefore: a.timeBefore))
              .toList(),
        );
      }
      await AlertNotifications.scheduleForTask(_buildSchedulingTask(taskId));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save task: $e')));
      }
    }
  }

  /// Builds a minimal [Task] containing only the fields [AlertNotifications]
  /// needs: id, text, dueAt, and alerts.
  Task _buildSchedulingTask(String taskId) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return Task(
      id: taskId,
      text: _textController.text.trim(),
      dueAt: _dueAt,
      alerts: _alerts.map((a) {
        if (a.alertAt != null) {
          return TaskAlert(id: 0, alertAt: a.alertAt);
        }
        final d = a.timeBefore!;
        return TaskAlert(
          id: 0,
          timeBefore:
              '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:${pad(d.inSeconds.remainder(60))}',
        );
      }).toList(),
      isOwner: true,
      createdAt: DateTime.now(),
      collaborators: [],
    );
  }

  String _formatDateTime(DateTime dt) {
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  String _formatAlert(_Alert alert) {
    if (alert.timeBefore != null) {
      final d = alert.timeBefore!;
      final hours = d.inHours;
      final minutes = d.inMinutes.remainder(60);
      if (hours > 0 && minutes > 0) return '$hours h $minutes min before';
      if (hours > 0) return '$hours h before';
      return '$minutes min before';
    }
    return _formatDateTime(alert.alertAt!);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_hasChanges) {
          Navigator.of(context).pop();
          return;
        }
        final confirmed = await showDialog<bool>(
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
        if (confirmed == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: true,
          title: Text(_isEditing ? 'Edit Task' : 'New Task'),
          actions: [
            if (_isEditing)
              IconButton(
                icon: _deleting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                tooltip: 'Delete task',
                onPressed: (_saving || _deleting)
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete task'),
                            content: const Text(
                              'This cannot be undone. Are you sure?',
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
                        if (confirmed != true || !mounted) return;
                        setState(() => _deleting = true);
                        try {
                          await widget.client.deleteTask(
                            taskId: widget.existingTask!.id,
                          );
                          await AlertNotifications.cancelForTask(
                            widget.existingTask!.id,
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
                        } catch (e) {
                          if (mounted) {
                            setState(() => _deleting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete task: $e'),
                              ),
                            );
                          }
                        }
                      },
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Task settings',
              onPressed: (_saving || _deleting)
                  ? null
                  : () async {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => TaskSettingsDialog(
                          initialColor: _color,
                          onApply: (color) => setState(() => _color = color),
                        ),
                      );
                    },
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _textController,
                autofocus: !_isEditing,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'Task',
                  hintText: 'What needs to be done?',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Task text is required'
                    : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  _dueAt != null ? _formatDateTime(_dueAt!) : 'No date set',
                  style: _dueAt == null
                      ? TextStyle(color: Theme.of(context).hintColor)
                      : null,
                ),
                trailing: _dueAt != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear date',
                        onPressed: () => setState(() {
                          _dueAt = null;
                          _rrule = '';
                        }),
                      )
                    : null,
                onTap: _pickDateTime,
              ),
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.notifications_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text('Alerts', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addAlert,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              ..._alerts.asMap().entries.map((e) {
                final index = e.key;
                final alert = e.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    alert.timeBefore != null
                        ? Icons.timer_outlined
                        : Icons.alarm,
                  ),
                  title: Text(_formatAlert(alert)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove alert',
                    onPressed: () => setState(() => _alerts.removeAt(index)),
                  ),
                );
              }),
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.people_outline, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Collaborators',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppUser>(
                decoration: const InputDecoration(
                  hintText: 'Add a collaborator…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                initialValue: null,
                items: widget.users
                    .where(
                      (u) =>
                          u.id != widget.currentUserId &&
                          !_collaborators.any((c) => c.id == u.id),
                    )
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text('${u.name} (${u.email})'),
                      ),
                    )
                    .toList(),
                onChanged: (u) {
                  if (u != null) setState(() => _collaborators.add(u));
                },
              ),
              ..._collaborators.asMap().entries.map((e) {
                final index = e.key;
                final user = e.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.name),
                  subtitle: Text(user.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: () =>
                        setState(() => _collaborators.removeAt(index)),
                  ),
                );
              }),
              const Divider(),
              const SizedBox(height: 8),
              Opacity(
                opacity: _dueAt != null ? 1.0 : 0.4,
                child: AbsorbPointer(
                  absorbing: _dueAt == null,
                  child: RRuleGenerator(
                config: RRuleGeneratorConfig(
                  headerStyle: const RRuleHeaderStyle(
                    textStyle: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  switchStyle: RRuleSwitchStyle(
                    isCupertinoStyle: true,
                    activeTrackColor: Colors.blue,
                    inactiveTrackColor: Colors.grey,
                  ),
                  datePickerStyle: RRuleDatePickerStyle(
                    datePickerButtonStyle: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      side: WidgetStateProperty.all(
                        BorderSide(color: Colors.blue, width: 1),
                      ),
                    ),
                    datePickerTextStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.blue,
                    ),
                  ),
                  divider: Divider(thickness: 0.5, color: Colors.blue),
                ),
                initialRRule: _rrule,
                withExcludeDates: true,
                onChange: (rrule) => _rrule = rrule,
                ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
