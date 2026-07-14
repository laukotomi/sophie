import 'package:flutter/material.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/storage.dart';

class SnoozePickerScreen extends StatelessWidget {
  final int alarmId;
  final String taskId;
  final String body;
  final DateTime? relativeDateTime;

  const SnoozePickerScreen({
    super.key,
    required this.alarmId,
    required this.taskId,
    required this.body,
    this.relativeDateTime,
  });

  static const _presets = [
    (label: '15 minutes', duration: Duration(minutes: 15)),
    (label: '30 minutes', duration: Duration(minutes: 30)),
    (label: '1 hour', duration: Duration(hours: 1)),
    (label: '2 hours', duration: Duration(hours: 2)),
  ];

  Future _snoozeFor(BuildContext context, Duration duration) async {
    final fireAt = (relativeDateTime ?? DateTime.now()).add(duration);
    await _setNewAlarm(context, fireAt);
  }

  Future _pickCustomTime(BuildContext context) async {
    final base = relativeDateTime ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null || !context.mounted) return;

    final fireAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (!fireAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a future date and time.')),
      );
      return;
    }

    await _setNewAlarm(context, fireAt);
  }

  Future _setNewAlarm(BuildContext context, DateTime fireAt) async {
    await AlertNotifications.rescheduleAlarm(alarmId, taskId, fireAt, body);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel snooze?'),
        content: const Text('The alarm will not ring again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep snooze'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel snooze'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await Storage.removeSnoozePending(alarmId);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snooze'),
        actions: [
          if (relativeDateTime == null)
            TextButton(
              onPressed: () => _cancel(context),
              child: const Text('Cancel snooze'),
            ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(body, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(),
          ..._presets.map(
            (p) => ListTile(
              title: Text(p.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _snoozeFor(context, p.duration),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Custom time...'),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickCustomTime(context),
          ),
        ],
      ),
    );
  }
}
