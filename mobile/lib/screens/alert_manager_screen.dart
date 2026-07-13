import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sophie/models/alert.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/storage.dart';

class AlertManagerScreen extends StatefulWidget {
  final List<Task> tasks;

  const AlertManagerScreen({super.key, required this.tasks});

  @override
  State<AlertManagerScreen> createState() => _AlertManagerScreenState();
}

class _AlertManagerScreenState extends State<AlertManagerScreen> {
  bool _loading = false;
  late List<_AlertEntry> _alerts;

  @override
  void initState() {
    super.initState();
    _alerts = _loadAlerts();
  }

  List<_AlertEntry> _loadAlerts() {
    final data = Storage.getDashboardData();
    if (data == null) return [];
    final now = DateTime.now();
    final mutedUntil = Storage.mutedUntil;
    final results = <_AlertEntry>[];
    for (final task in data.tasks.where((t) => t.doneAt == null)) {
      for (final alert in task.alerts) {
        final fireAt = _resolveFireAt(alert, task.dueAt);
        if (fireAt == null || !fireAt.isAfter(now)) continue;
        results.add((
          fireAt: fireAt,
          taskText: task.text,
          muted: mutedUntil != null && fireAt.isBefore(mutedUntil),
        ));
      }
    }
    results.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return results;
  }

  static DateTime? _resolveFireAt(Alert alert, DateTime? dueAt) {
    if (alert.alertAt != null) return alert.alertAt;
    if (alert.timeBefore != null && dueAt != null) {
      return dueAt.subtract(alert.timeBefore!);
    }
    return null;
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
                    entry.muted ? Icons.notifications_paused : Icons.alarm,
                    color: entry.muted
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                  title: Text(entry.taskText),
                  subtitle: Text(
                    DateFormat('MMM d, HH:mm').format(entry.fireAt),
                  ),
                  trailing: entry.muted
                      ? Text(
                          'muted',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

typedef _AlertEntry = ({DateTime fireAt, String taskText, bool muted});
