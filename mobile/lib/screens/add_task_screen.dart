import 'package:flutter/material.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:sophie/backend.dart';

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

  const AddTaskScreen({
    super.key,
    required this.users,
    required this.currentUserId,
    required this.client,
  });

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  bool _saving = false;
  DateTime? _dueAt;
  String _rrule = '';
  final List<_Alert> _alerts = [];
  final List<AppUser> _collaborators = [];

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
      await widget.client.createTask(
        text: _textController.text.trim(),
        rrule: _rrule.isNotEmpty ? _rrule : null,
        dueAt: _dueAt,
        collaboratorIds: _collaborators.map((u) => u.id).toList(),
        alerts: _alerts
            .map((a) => (alertAt: a.alertAt, timeBefore: a.timeBefore))
            .toList(),
      );
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
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: const Text('New Task'),
        actions: [
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
              autofocus: true,
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
                      onPressed: () => setState(() => _dueAt = null),
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
                  alert.timeBefore != null ? Icons.timer_outlined : Icons.alarm,
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
            RRuleGenerator(
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
          ],
        ),
      ),
    );
  }
}
