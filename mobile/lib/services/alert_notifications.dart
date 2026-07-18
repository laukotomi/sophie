import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sophie/events/task_set_done_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/alert.dart';
import 'package:sophie/models/scheduled_notification.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/screens/snooze_picker_screen.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/task_events.dart';

enum AlertTypes { alarm, notification, both }

class AlertNotifications {
  static const _actionsChannelKey = 'task_alarm_actions';
  static const _stopActionKey = 'STOP_ALARM';
  static const _doneActionKey = 'MARK_DONE';
  static const _snoozeActionKey = 'SNOOZE';

  static Future init() async {
    await _initAwesomeNotifications();
    await Alarm.init();
  }

  static Future requestPermissions() async {
    await Permission.notification.request();
    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  static Future<List<ScheduledNotification>> scheduleAlerts(
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

    for (final alert in alerts) {
      DateTime? fireAt = _resolveFireAt(alert, taskDueAt);
      if (fireAt == null || !fireAt.isAfter(now)) continue;

      final alarmId = _notifId(taskId, notifications.length);
      final rescheduledAt =
          rescheduledAlarms != null && rescheduledAlarms.containsKey(alarmId)
          ? rescheduledAlarms[alarmId]
          : null;

      if (rescheduledAt != null) {
        // This alert was snoozed and rescheduled by the user. Use the new time.
        fireAt = rescheduledAt;
      }

      final muted = mutedUntil != null && !fireAt.isAfter(mutedUntil);
      final notification = await _setAlarmAt(
        alarmId,
        fireAt,
        taskId,
        text,
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
    await _cancelByAlarmId(alarmId);
    final notification = await _setAlarmAt(alarmId, fireAt, taskId, text);
    notification.rescheduled = true;
    await Storage.updateTaskAlerts([notification]);
  }

  static Future refreshNotifications(List<Task> freshTasks) async {
    final alerts = Storage.getAllScheduledNotifications();

    Map<int, DateTime> rescheduledAlarms = {
      for (final a in alerts.where((a) => a.rescheduled))
        a.id: a.scheduledDateTime,
    };

    await Alarm.stopAll();
    await AwesomeNotifications().cancelAll();

    Map<String, List<ScheduledNotification>> taskAlertsMap = {};

    // Schedule fresh alarms for all pending tasks.
    for (final task in freshTasks.where(
      (t) => t.doneAt == null && t.alerts.isNotEmpty,
    )) {
      final notifications = await scheduleAlerts(
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
      await _cancelByAlarmId(alert.id);
    }
    if (save) await Storage.removeTaskAlerts(taskId);
  }

  static Future cancelAlarm(ScheduledNotification alarm) async {
    await _cancelByAlarmId(alarm.id);
    await Storage.removeTaskAlert(alarm.taskId, alarm.id);
  }

  static Future muteUntil(DateTime until) async {
    final alerts = Storage.getAllScheduledNotifications();
    List<ScheduledNotification> updated = [];

    for (final alert in alerts) {
      if (alert.muted || alert.scheduledDateTime.isAfter(until)) continue;

      await _cancelByAlarmId(alert.id, alertType: AlertTypes.alarm);
      alert.muted = true;
      updated.add(alert);
    }

    if (updated.isNotEmpty) {
      await Storage.updateTaskAlerts(updated);
    }
    await Storage.setMutedUntil(until);
  }

  static Future cancelMute() async {
    final alerts = Storage.getAllScheduledNotifications();
    List<ScheduledNotification> updated = [];

    for (final alert in alerts) {
      if (!alert.muted) continue;

      final notification = await _setAlarmAt(
        alert.id,
        alert.scheduledDateTime,
        alert.taskId,
        alert.body,
        alertType: AlertTypes.alarm,
      );

      updated.add(notification);
    }

    if (updated.isNotEmpty) {
      await Storage.updateTaskAlerts(updated);
    }
    await Storage.clearMutedUntil();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Future<ScheduledNotification> _setAlarmAt(
    int alarmId,
    DateTime fireAt,
    String taskId,
    String text, {
    AlertTypes alertType = AlertTypes.both,
  }) async {
    if (alertType == AlertTypes.alarm || alertType == AlertTypes.both) {
      final alarmSettings = AlarmSettings(
        id: alarmId,
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
          body: text,
          stopButton: 'Stop the alarm',
          icon: 'notification_icon',
          iconColor: Color(0xff862778),
        ),
      );
      await Alarm.set(alarmSettings: alarmSettings);
    }

    if (alertType == AlertTypes.notification || alertType == AlertTypes.both) {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: alarmId,
          channelKey: _actionsChannelKey,
          title: 'Sophie',
          body: text,
          payload: {'alarmId': '$alarmId', 'taskId': taskId},
          autoDismissible: false,
          wakeUpScreen: true,
          actionType: ActionType.DisabledAction,
        ),
        schedule: NotificationCalendar.fromDate(
          date: fireAt.add(Duration(seconds: 1)),
          allowWhileIdle: true,
          preciseAlarm: true,
        ),
        actionButtons: [
          NotificationActionButton(key: _stopActionKey, label: 'Stop'),
          NotificationActionButton(key: _doneActionKey, label: 'Mark done'),
          NotificationActionButton(key: _snoozeActionKey, label: 'Snooze..'),
        ],
      );
    }

    return ScheduledNotification(
      id: alarmId,
      scheduledDateTime: fireAt,
      body: text,
      muted: alertType == AlertTypes.notification,
      taskId: taskId,
    );
  }

  static Future _cancelByAlarmId(
    int alarmId, {
    AlertTypes alertType = AlertTypes.both,
  }) async {
    try {
      if (alertType == AlertTypes.alarm || alertType == AlertTypes.both) {
        await Alarm.stop(alarmId);
      }
    } catch (_) {
      // Ignore errors if the alarm was already stopped or dismissed.
    }

    try {
      if (alertType == AlertTypes.notification ||
          alertType == AlertTypes.both) {
        await AwesomeNotifications().dismiss(alarmId);
      }
    } catch (_) {
      // Ignore errors if the notification was already dismissed.
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

  static Future _initAwesomeNotifications() async {
    await AwesomeNotifications().initialize(null, [
      NotificationChannel(
        channelGroupKey: 'sophie_tasks',
        channelKey: _actionsChannelKey,
        channelName: 'Task alarm actions',
        channelDescription: 'Actions for active task alarms',
        importance: NotificationImportance.Max,
        playSound: false,
        enableVibration: false,
      ),
    ]);

    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onNotificationAction,
      onDismissActionReceivedMethod: _onNotificationDismiss,
    );
  }

  @pragma('vm:entry-point')
  static Future _onNotificationAction(ReceivedAction action) async {
    await Storage.init();

    final alarmId = int.tryParse(action.payload?['alarmId'] ?? '');
    final taskId = action.payload?['taskId'];
    if (alarmId == null || taskId == null || action.body == null) return;

    await Storage.removeTaskAlert(taskId, alarmId);
    await _cancelByAlarmId(alarmId);

    if (action.buttonKeyPressed == _stopActionKey) {
      return;
    }

    if (action.buttonKeyPressed == _snoozeActionKey) {
      await Storage.addSnoozePending(alarmId, taskId, action.body!);
      await navigatorKey.currentState?.push<void>(
        MaterialPageRoute(
          builder: (_) => SnoozePickerScreen(
            alarmId: alarmId,
            taskId: taskId,
            body: action.body!,
          ),
        ),
      );
      return;
    }

    if (action.buttonKeyPressed == _doneActionKey) {
      await _markTaskDone(taskId);
    }
  }

  static Future _markTaskDone(String taskId) async {
    await cancelForTask(taskId);

    final data = Storage.getDashboardData();
    if (data == null) return;
    final task = data.tasks.firstWhere((t) => t.id == taskId);
    await TaskEventBus.instance.emit(
      TaskSetDoneEvent(doneAt: DateTime.now(), task: task),
    );
  }

  static Future _onNotificationDismiss(ReceivedAction action) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: action.id!,
        channelKey: _actionsChannelKey,
        title: 'Sophie',
        body: action.body,
        payload: action.payload,
        autoDismissible: false,
        wakeUpScreen: true,
        actionType: ActionType.DisabledAction,
      ),
      actionButtons: [
        NotificationActionButton(key: _stopActionKey, label: 'Stop'),
        NotificationActionButton(key: _doneActionKey, label: 'Mark done'),
        NotificationActionButton(key: _snoozeActionKey, label: 'Snooze..'),
      ],
    );
  }
}
