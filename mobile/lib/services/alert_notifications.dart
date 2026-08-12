import 'dart:async';

import 'package:sophie/models/alert.dart';
import 'package:sophie/models/scheduled_notification.dart';
import 'package:sophie/models/settings.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alerts.dart';
import 'package:sophie/services/storage.dart';

class AlertNotifications {
  static Future<List<ScheduledNotification>> scheduleAlertsForTask(
    String taskId,
    DateTime? taskDueAt,
    List<Alert> alerts,
    String text, {
    Map<int, DateTime>? rescheduledAlarms,
    bool save = true,
  }) async {
    await cancelForTask(taskId, save: false);

    List<ScheduledNotification> notifications = [];
    final now = DateTime.now();
    final mutedUntil = Storage.mutedUntil;
    final settings = Storage.getSettings() ?? Settings();

    for (var i = 0; i < alerts.length; i++) {
      final alert = alerts[i];
      final alarmId = _notifId(taskId, i);

      final rescheduledAt = rescheduledAlarms?[alarmId];
      final fireAt = rescheduledAt ?? _resolveFireAt(alert, taskDueAt);
      if (fireAt == null || !fireAt.isAfter(now)) continue;

      final muted = mutedUntil != null && !fireAt.isAfter(mutedUntil);

      final notification = await Alerts.setAlarmAt(
        alarmId,
        fireAt,
        taskId,
        text,
        settings,
        alertType: muted ? AlertTypes.notification : AlertTypes.both,
      );

      notification.rescheduled = rescheduledAt != null;
      notifications.add(notification);
    }

    if (notifications.isNotEmpty && save) {
      await Storage.setTaskAlerts(taskId, notifications);
    }

    return notifications;
  }

  // Called when snoozing an alarm
  static Future rescheduleAlarm(
    int alarmId,
    String taskId,
    DateTime fireAt,
    String text,
  ) async {
    await Alerts.cancelByAlarmId(alarmId);
    final settings = Storage.getSettings() ?? Settings();

    final muted =
        Storage.mutedUntil != null && !fireAt.isAfter(Storage.mutedUntil!);

    final notification = await Alerts.setAlarmAt(
      alarmId,
      fireAt,
      taskId,
      text,
      settings,
      alertType: muted ? AlertTypes.notification : AlertTypes.both,
    );

    notification.rescheduled = true;
    await Storage.updateTaskAlerts([notification]);
  }

  static Future refreshNotifications(List<Task> freshTasks) async {
    final alerts = Storage.getAllScheduledNotifications();

    Map<int, DateTime> rescheduledAlarms = {
      for (final a in alerts.where((a) => a.rescheduled))
        a.id: a.scheduledDateTime,
    };

    await Alerts.clear();
    Map<String, List<ScheduledNotification>> taskAlertsMap = {};

    // Schedule fresh alarms for all pending tasks.
    for (final task in freshTasks.where(
      (t) => t.doneAt == null && t.alerts.isNotEmpty,
    )) {
      final notifications = await scheduleAlertsForTask(
        task.id,
        task.dueAt,
        task.alerts,
        task.text,
        rescheduledAlarms: rescheduledAlarms,
        save: false,
      );

      taskAlertsMap[task.id] = notifications;
    }

    await Storage.setTaskAlertsMap(taskAlertsMap);
  }

  static Future cancelForTask(String taskId, {bool save = true}) async {
    final alerts = Storage.getTaskAlerts(taskId);
    for (final alert in alerts) {
      await Alerts.cancelByAlarmId(alert.id);
    }
    if (save) await Storage.removeTaskAlerts(taskId);
  }

  static Future cancelAlarm(ScheduledNotification alarm) async {
    await Alerts.cancelByAlarmId(alarm.id);
    await Storage.removeTaskAlert(alarm.taskId, alarm.id);
  }

  static Future muteUntil(DateTime until) async {
    final alerts = Storage.getAllScheduledNotifications();
    List<ScheduledNotification> updated = [];

    for (final alert in alerts) {
      if (alert.muted || alert.scheduledDateTime.isAfter(until)) continue;

      await Alerts.cancelByAlarmId(alert.id, alertType: AlertTypes.alarm);
      alert.muted = true;
      updated.add(alert);
    }

    if (updated.isNotEmpty) {
      await Storage.updateTaskAlerts(updated);
    }
  }

  static Future cancelMute() async {
    final alerts = Storage.getAllScheduledNotifications();
    final settings = Storage.getSettings() ?? Settings();
    List<ScheduledNotification> updated = [];

    for (final alert in alerts) {
      if (!alert.muted) continue;

      await Alerts.setAlarmAt(
        alert.id,
        alert.scheduledDateTime,
        alert.taskId,
        alert.body,
        settings,
        alertType: AlertTypes.alarm,
      );

      alert.muted = false;
      updated.add(alert);
    }

    if (updated.isNotEmpty) {
      await Storage.updateTaskAlerts(updated);
    }
  }

  /// Resolves the absolute fire time from an alert definition.
  static DateTime? _resolveFireAt(Alert alert, DateTime? dueAt) {
    if (alert.alertAt != null) return alert.alertAt;
    if (alert.timeBefore != null && dueAt != null) {
      return dueAt.subtract(alert.timeBefore!);
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
