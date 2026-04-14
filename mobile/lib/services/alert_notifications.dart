import 'dart:io';
import 'dart:ui';

import 'package:alarm/alarm.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sophie/models.dart';
import 'package:sophie/storage.dart';

/// Manages scheduling of task alert notifications.
///
/// Lifecycle:
/// 1. Call [init] once from [main] — safe with no Activity.
/// 2. Call [requestPermissions] from a widget's [State.initState] — requires
///    a live Activity for the permission dialog.
/// 3. Call [scheduleForTask] after every task create / update.
/// 4. Call [cancelForTask] after a task is deleted.
class AlertNotifications {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initialises the alarm package.
  /// Safe to call from [main] before [runApp].
  static Future<void> init() async {
    await Alarm.init();
  }

  /// Requests the permissions required for alarms and notifications.
  /// Must be called from a widget with a live Activity (e.g. [State.initState]).
  static Future<void> requestPermissions() async {
    await Permission.notification.request();
    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Cancels any existing alerts for [task] and schedules new ones for every
  /// future alert time defined on the task.
  static Future<void> scheduleForTask(Task task) async {
    await cancelForTask(task.id);

    final newIds = <int>[];
    final now = DateTime.now();

    for (final alert in task.alerts) {
      final fireAt = _resolveFireAt(alert, task.dueAt);
      if (fireAt == null || !fireAt.isAfter(now)) continue;

      final id = _notifId(task.id, newIds.length);
      final alarmSettings = AlarmSettings(
        id: id,
        dateTime: fireAt,
        assetAudioPath: 'assets/task_alert.mp3',
        loopAudio: true,
        vibrate: true,
        warningNotificationOnKill: Platform.isIOS,
        androidFullScreenIntent: false,
        volumeSettings: VolumeSettings.fade(
          volume: 0.5,
          fadeDuration: Duration(seconds: 5),
          volumeEnforced: false,
        ),
        notificationSettings: NotificationSettings(
          title: 'Sophie',
          body: task.text,
          stopButton: 'Stop the alarm',
          icon: 'notification_icon',
          iconColor: Color(0xff862778),
        ),
      );
      await Alarm.set(alarmSettings: alarmSettings);
      newIds.add(id);
    }

    if (newIds.isNotEmpty) {
      await Storage.setAlertCount(task.id, newIds.length);
    }
  }

  /// Cancels all pending notifications that were scheduled for [taskId].
  static Future<void> cancelForTask(String taskId) async {
    final count = Storage.getAlertCount(taskId);
    for (var i = 0; i < count; i++) {
      await Alarm.stop(_notifId(taskId, i));
    }
    await Storage.removeAlertCount(taskId);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Resolves the absolute fire time from an alert definition.
  static DateTime? _resolveFireAt(TaskAlert alert, DateTime? dueAt) {
    if (alert.alertAt != null) return alert.alertAt;
    if (alert.timeBefore != null && dueAt != null) {
      // timeBefore is stored as 'HH:MM:SS'
      final parts = alert.timeBefore!.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      return dueAt.subtract(Duration(hours: h, minutes: m));
    }
    return null;
  }

  /// Returns a stable, non-negative int32 notification ID derived from the
  /// backend task ID and the alert's index within that task. Using the task ID
  /// from the server means IDs are deterministic — no local counter needed.
  /// (Dart's built-in hashCode is NOT stable across restarts, so we use djb2.)
  static int _notifId(String taskId, int alertIndex) {
    var h = 5381;
    for (final c in taskId.codeUnits) {
      h = (((h << 5) + h) ^ c) & 0x7FFFFFFF;
    }
    return h + alertIndex;
  }
}
