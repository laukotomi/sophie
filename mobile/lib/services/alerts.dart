import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sophie/events/task_set_done_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/scheduled_notification.dart';
import 'package:sophie/models/settings.dart';
import 'package:sophie/screens/snooze_picker_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/task_events.dart';

enum AlertTypes { alarm, notification, both }

class Alerts {
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

  static Future clear() async {
    await Alarm.stopAll();
    await AwesomeNotifications().cancelAll();
  }

  static Future<ScheduledNotification> setAlarmAt(
    int alarmId,
    DateTime fireAt,
    String taskId,
    String text,
    Settings settings, {
    AlertTypes alertType = AlertTypes.both,
  }) async {
    if (alertType == AlertTypes.alarm || alertType == AlertTypes.both) {
      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: fireAt,
        assetAudioPath: settings.alarmSound.path,
        loopAudio: true,
        vibrate: false,
        warningNotificationOnKill: Platform.isIOS,
        androidFullScreenIntent: false,
        volumeSettings: VolumeSettings.fade(
          volume: settings.alarmVolume,
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

  static Future cancelByAlarmId(
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
        await AwesomeNotifications().cancel(alarmId);
      }
    } catch (_) {
      // Ignore errors if the notification was already dismissed.
    }
  }

  static Future _initAwesomeNotifications() async {
    await AwesomeNotifications().initialize(null, [
      NotificationChannel(
        channelGroupKey: 'sophie_tasks',
        channelKey: _actionsChannelKey,
        channelName: 'Task alarm actions',
        channelDescription: 'Actions for active task alarms',
        importance: NotificationImportance.High,
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

    await cancelByAlarmId(alarmId);

    switch (action.buttonKeyPressed) {
      case _stopActionKey:
        await Storage.removeTaskAlert(taskId, alarmId);
        break;

      case _snoozeActionKey:
        await Storage.addSnoozePending(alarmId, taskId, action.body!);
        await navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => SnoozePickerScreen(
              alarmId: alarmId,
              taskId: taskId,
              body: action.body!,
            ),
          ),
        );
        break;

      case _doneActionKey:
        await AlertNotifications.cancelForTask(taskId);
        await TaskEventBus.instance.emit(
          TaskSetDoneEvent(doneAt: DateTime.now(), taskId: taskId),
        );

        break;
    }
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
