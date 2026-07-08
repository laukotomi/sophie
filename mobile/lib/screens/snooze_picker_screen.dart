import 'package:flutter/material.dart';
import 'package:sophie/services/alert_notifications.dart';

class SnoozePickerScreen extends StatelessWidget {
  final int alarmId;
  final String taskId;
  final String? body;

  const SnoozePickerScreen({
    super.key,
    required this.alarmId,
    required this.taskId,
    this.body,
  });

  static const _presets = [
    (label: '15 minutes', duration: Duration(minutes: 15)),
    (label: '30 minutes', duration: Duration(minutes: 30)),
    (label: '1 hour', duration: Duration(hours: 1)),
    (label: '2 hours', duration: Duration(hours: 2)),
  ];

  Future _snoozeFor(BuildContext context, Duration duration) async {
    final fireAt = DateTime.now().add(duration);
    await AlertNotifications.setAlarmAt(alarmId, fireAt, taskId, body ?? '');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future _pickCustomTime(BuildContext context) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null || !context.mounted) return;

    final today = DateTime.now();
    var fireAt = DateTime(
      today.year,
      today.month,
      today.day,
      picked.hour,
      picked.minute,
    );
    // If the picked time is in the past today, schedule for tomorrow.
    if (!fireAt.isAfter(today)) {
      fireAt = fireAt.add(const Duration(days: 1));
    }
    await AlertNotifications.setAlarmAt(alarmId, fireAt, taskId, body ?? '');
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snooze')),
      body: ListView(
        children: [
          if (body != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                body!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
