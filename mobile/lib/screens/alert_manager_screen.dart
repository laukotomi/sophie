import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sophie/models/scheduled_notification.dart';
import 'package:sophie/screens/snooze_picker_screen.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/storage.dart';

class AlertManagerScreen extends StatefulWidget {
  const AlertManagerScreen({super.key, required this.tasks});

  final List<Task> tasks;

  @override
  State<AlertManagerScreen> createState() => _AlertManagerScreenState();
}

class _AlertManagerScreenState extends State<AlertManagerScreen> {
  bool _loading = false;
  late List<ScheduledNotification> _alerts;

  @override
  void initState() {
    super.initState();
    _alerts = _loadAlerts();
  }

  List<ScheduledNotification> _loadAlerts() {
    final taskAlertsMap = Storage.getTaskAlertsMap();
    List<ScheduledNotification> alerts = [];
    for (final taskId in taskAlertsMap.keys) {
      final taskAlerts = taskAlertsMap[taskId]!;
      alerts.addAll(taskAlerts);
    }
    alerts.sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
    return alerts;
  }

  Future _confirmCancelAlert(ScheduledNotification entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel alert?'),
        content: Text(
          'The alert for "${entry.body}" at '
          '${DateFormat('MMM d, HH:mm').format(entry.scheduledDateTime)} '
          'will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel alert'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AlertNotifications.cancelAlarm(entry);
      if (mounted) {
        setState(() {
          _alerts = _loadAlerts();
        });
      }
    }
  }

  Future _openSnoozePicker(ScheduledNotification entry) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SnoozePickerScreen(
          alarmId: entry.id,
          taskId: entry.taskId,
          body: entry.body,
          relativeDateTime: entry.scheduledDateTime,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _alerts = _loadAlerts();
      });
    }
  }

  Future _mute() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 1, minute: 0),
      helpText: 'Mute alerts for (HH:MM)',
      hourLabelText: 'Hours',
      minuteLabelText: 'Minutes',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final duration = Duration(hours: picked.hour, minutes: picked.minute);
    if (duration == Duration.zero) return;

    setState(() => _loading = true);
    try {
      final until = DateTime.now().add(duration);
      await AlertNotifications.muteUntil(until, widget.tasks);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _alerts = _loadAlerts();
        });
      }
    }
  }

  Future _cancelMute() async {
    setState(() => _loading = true);
    try {
      await AlertNotifications.cancelMute(widget.tasks);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _alerts = _loadAlerts();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedUntil = Storage.mutedUntil;
    final muted = mutedUntil != null;
    final mutedUntilStr = muted
        ? DateFormat('MMM d, HH:mm').format(mutedUntil)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Task Alerts')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Sound',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ListTile(
            leading: Icon(
              muted ? Icons.notifications_off : Icons.notifications_active,
              color: muted ? theme.colorScheme.error : null,
            ),
            title: Text(muted ? 'Muted until $mutedUntilStr' : 'Alerts active'),
            subtitle: Text(
              muted
                  ? 'Alarm sounds are suppressed. Notifications are still delivered silently.'
                  : 'All alert sounds are enabled.',
            ),
            trailing: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : muted
                ? FilledButton.tonal(
                    onPressed: _cancelMute,
                    child: const Text('Unmute'),
                  )
                : FilledButton(onPressed: _mute, child: const Text('Mute')),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Upcoming alerts',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (_alerts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'No upcoming alerts.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Column(
              children: _alerts.map((entry) {
                return ListTile(
                  leading: Icon(
                    entry.muted ? Icons.volume_off : Icons.alarm,
                    color: entry.muted
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                  title: Text(entry.body),
                  subtitle: Text(
                    DateFormat('MMM d, HH:mm').format(entry.scheduledDateTime),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.muted)
                        Text(
                          'muted',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.snooze_outlined),
                        tooltip: 'Snooze alert',
                        onPressed: () => _openSnoozePicker(entry),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.cancel_outlined,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: 'Cancel alert',
                        onPressed: () => _confirmCancelAlert(entry),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
