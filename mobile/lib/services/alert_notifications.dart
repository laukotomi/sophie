import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/alert.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/snooze_picker_screen.dart';
import 'package:sophie/services/storage.dart';

/// Manages scheduling of task alert notifications.
///
/// Lifecycle:
/// 1. Call [init] once from [main] — safe with no Activity.
/// 2. Call [requestPermissions] from a widget's [State.initState] — requires
///    a live Activity for the permission dialog.
/// 3. Call [scheduleAlerts] after every task create / update.
/// 4. Call [cancelForTask] after a task is deleted.
class AlertNotifications {
  static const _actionsChannelKey = 'task_alarm_actions';
  static const _stopActionKey = 'STOP_ALARM';
  static const _doneActionKey = 'MARK_DONE';
  static const _snoozeActionKey = 'SNOOZE';

  /// Initialises the alarm package.
  /// Safe to call from [main] before [runApp].
  static Future init() async {
    await _initAwesomeNotifications();
    await Alarm.init();
  }

  /// Requests the permissions required for alarms and notifications.
  /// Must be called from a widget with a live Activity (e.g. [State.initState]).
  static Future requestPermissions() async {
    await Permission.notification.request();
    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Cancels any existing alerts for [task] and schedules new ones for every
  /// future alert time defined on the task.
  static Future scheduleAlerts(
    String taskId,
    DateTime? taskDueAt,
    List<Alert> alerts,
    String text,
  ) async {
    await cancelForTask(taskId);

    int alertCount = 0;
    final now = DateTime.now();

    for (final alert in alerts) {
      final fireAt = _resolveFireAt(alert, taskDueAt);
      if (fireAt == null || !fireAt.isAfter(now)) continue;

      final alarmId = _notifId(taskId, alertCount);
      setAlarmAt(alarmId, fireAt, taskId, text);

      alertCount++;
    }

    if (alertCount > 0) {
      await Storage.setAlertCount(taskId, alertCount);
    }
  }

  static Future setAlarmAt(
    int alarmId,
    DateTime fireAt,
    String taskId,
    String text,
  ) async {
    final alarmSettings = AlarmSettings(
      id: alarmId,
      dateTime: fireAt,
      // payload: jsonEncode({'taskId': task.id}),
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

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: alarmId,
        channelKey: _actionsChannelKey,
        title: 'Sophie',
        body: text,
        payload: {'alarmId': '$alarmId', 'taskId': taskId},
        autoDismissible: false,
        wakeUpScreen: true,
        locked: true,
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

  /// Cancels all existing alarms (derived from the old cached data) then
  /// reschedules from [freshTasks]. Call this after every dashboard refresh.
  static Future rescheduleAll(List<Task> freshTasks) async {
    // Cancel alarms for every previously tracked task, including ones that may
    // have been deleted from the server since the last launch.
    final cachedData = Storage.getAlertCountsMap();
    for (final taskId in cachedData.keys) {
      await cancelForTask(taskId);
    }
    // Schedule fresh alarms for all pending tasks.
    for (final task in freshTasks.where((t) => t.doneAt == null)) {
      await scheduleAlerts(task.id, task.dueAt, task.alerts, task.text);
    }
  }

  static Future cancelForTask(String taskId) async {
    final count = Storage.getAlertCount(taskId);
    for (var i = 0; i < count; i++) {
      final alarmId = _notifId(taskId, i);
      await cancelByAlarmId(alarmId);
    }
    await Storage.removeAlertCount(taskId);
  }

  static Future cancelByAlarmId(int alarmId) async {
    try {
      await Alarm.stop(alarmId);
      await AwesomeNotifications().dismiss(alarmId);
    } catch (_) {
      // Ignore errors if the alarm was already stopped or dismissed.
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

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
    );
  }

  @pragma('vm:entry-point')
  static Future _onNotificationAction(ReceivedAction action) async {
    final alarmId = int.tryParse(action.payload?['alarmId'] ?? '');
    final taskId = action.payload?['taskId'];
    if (alarmId == null || taskId == null || action.body == null) return;

    await cancelByAlarmId(alarmId);
    if (action.buttonKeyPressed == _stopActionKey) {
      return;
    }

    await Storage.init();

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
    final serverUrl = Storage.serverUrl;
    final token = Storage.authToken;
    if (serverUrl == null || token == null) return;

    final client = BackendClient(baseUrl: serverUrl, token: token);

    await client.task.setTaskDone(taskId: taskId, done: true);
    await cancelForTask(taskId);
    AppEventBus.instance.emit(AppSyncEvent());
  }
}
