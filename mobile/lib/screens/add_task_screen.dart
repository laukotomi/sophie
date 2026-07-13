import 'package:flutter/material.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/alert.dart';
import 'package:sophie/models/app_user.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_task.dart';
import 'package:sophie/services/task_events.dart';
import 'package:sophie/services/user_service.dart';
import 'package:sophie/dialogs/discard_dialog.dart';
import 'package:sophie/dialogs/task_settings_dialog.dart';

class AddTaskScreen extends StatefulWidget {
  // When non-null the screen is in edit mode
  final Task? existingTask;
  final bool offlineMode;

  const AddTaskScreen({super.key, this.existingTask, this.offlineMode = false});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _users = getIt<UserService>().users;
  final _currentUserId = getIt<UserService>().currentUserId;
  late final TextEditingController _textController;

  late DateTime? _dueAt;
  late String _rrule;
  late final List<Alert> _alerts;
  late final List<AppUser> _collaborators;
  String? _color;

  bool _saving = false;
  bool _deleting = false;

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
    final currentCollabIds = _collaborators.map((u) => u.id).toSet();
    return _textController.text.trim() != t.text.trim() ||
        _dueAt != t.dueAt ||
        _rrule != (t.rrule ?? '') ||
        _color != t.color ||
        t.collaborators.length != currentCollabIds.length ||
        !(currentCollabIds.containsAll(t.collaborators)) ||
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
    _alerts = t?.alerts ?? [];

    // Pre-populate collaborators from existing task
    _collaborators = t == null
        ? []
        : t.collaborators
              .map((userId) => _users.where((u) => u.id == userId).firstOrNull)
              .whereType<AppUser>()
              .toList();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future _pickDateTime() async {
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

  Future _addAlert() async {
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
      if (diff.isNegative) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alert must be before the due date.')),
          );
        }
        return;
      }
      setState(() => _alerts.add(Alert.relative(diff)));
    } else {
      setState(() => _alerts.add(Alert.absolute(picked)));
    }
  }

  void _addRelativeAlert(Duration timeBefore) {
    setState(() => _alerts.add(Alert.relative(timeBefore)));
  }

  Future _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final event = TaskSavedEvent(
        taskId: widget.existingTask?.id,
        text: _textController.text.trim(),
        alerts: _alerts,
        collaboratorIds: _collaborators.map((u) => u.id).toList(),
        color: _color,
        dueAt: _dueAt,
        rrule: _rrule.isNotEmpty ? _rrule : null,
      );

      if (widget.offlineMode) {
        TaskEventBus.instance.emit(event);
      } else {
        await getIt<BackendTask>().saveTask(event);
      }

      await AlertNotifications.scheduleAlerts(
        event.taskId,
        event.dueAt,
        event.alerts,
        event.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save task: $e')));
      }
    }
  }

  Future _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task'),
        content: const Text('This cannot be undone. Are you sure?'),
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
      if (widget.offlineMode) {
        TaskEventBus.instance.emit(
          TaskDeletedEvent(taskId: widget.existingTask!.id),
        );
      } else {
        await getIt<BackendTask>().deleteTask(taskId: widget.existingTask!.id);
      }
      await AlertNotifications.cancelForTask(widget.existingTask!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete task: $e')));
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  static const _alertPresets = [
    (label: 'At due time', duration: Duration(seconds: 0)),
    (label: '5 min before', duration: Duration(minutes: 5)),
    (label: '15 min before', duration: Duration(minutes: 15)),
    (label: '30 min before', duration: Duration(minutes: 30)),
    (label: '1 h before', duration: Duration(hours: 1)),
  ];

  String _formatAlert(Alert alert) {
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
        final confirmed = await showDiscardDialog(context);
        if (confirmed == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: true,
          title: Text(_isEditing ? 'Edit Task' : 'New Task'),
          actions: [
            if (widget.offlineMode)
              const Tooltip(
                message: 'Offline — changes will sync when connected',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.cloud_off, color: Colors.orange),
                ),
              ),
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
                onPressed: (_saving || _deleting) ? null : _delete,
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
                minLines: 2,
                maxLines: null,
                decoration: const InputDecoration(
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
                          _alerts.removeWhere((a) => a.timeBefore != null);
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
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in _alertPresets)
                    ActionChip(
                      label: Text(preset.label),
                      onPressed: _dueAt != null
                          ? () => _addRelativeAlert(preset.duration)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
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
                key: ValueKey(_collaborators.length),
                decoration: const InputDecoration(
                  hintText: 'Add a collaborator…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                initialValue: null,
                items: _users
                    .where(
                      (u) =>
                          u.id != _currentUserId &&
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
              ..._collaborators.map((u) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _collaborators.remove(u)),
                  ),
                );
              }),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Opacity(
                opacity: _dueAt != null ? 1.0 : 0.4,
                child: AbsorbPointer(
                  absorbing: _dueAt == null,
                  child: RRuleGenerator(
                    key: ValueKey(_dueAt),
                    initialDate: _dueAt,
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
