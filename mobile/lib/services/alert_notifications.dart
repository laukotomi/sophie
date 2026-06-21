import 'dart:io';
import 'dart:convert';
import 'dart:ui';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sophie/backend.dart';
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
  static const _actionsChannelKey = 'task_alarm_actions';
  static const _snoozeChannelKey = 'task_snooze_alarm';
  static const _stopActionKey = 'STOP_ALARM';
  static const _doneActionKey = 'MARK_DONE';
  static const _snoozeActionKey = 'SNOOZE';
  static Set<int> _knownRingingIds = <int>{};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initialises the alarm package.
  /// Safe to call from [main] before [runApp].
  static Future<void> init() async {
    await _initActionNotifications();
    await Alarm.init();
    _startRingingListener();
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
        payload: jsonEncode({'taskId': task.id}),
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

  /// Cancels all existing alarms (derived from the old cached data) then
  /// reschedules from [freshTasks]. Call this after every dashboard refresh.
  static Future<void> rescheduleAll(List<Task> freshTasks) async {
    // Cancel alarms for every previously tracked task, including ones that may
    // have been deleted from the server since the last launch.
    final cachedData = Storage.getDashboardData();
    if (cachedData != null) {
      for (final task in cachedData.tasks) {
        await cancelForTask(task.id);
      }
    }
    // Schedule fresh alarms for all pending tasks.
    for (final task in freshTasks.where((t) => t.doneAt == null)) {
      await scheduleForTask(task);
    }
  }

  /// Cancels all pending notifications that were scheduled for [taskId].
  static Future<void> cancelForTask(String taskId) async {
    final count = Storage.getAlertCount(taskId);
    for (var i = 0; i < count; i++) {
      final alarmId = _notifId(taskId, i);
      await Alarm.stop(alarmId);
      await AwesomeNotifications().dismiss(_actionNotifId(alarmId));
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

  static int _actionNotifId(int alarmId) => (alarmId % 1000000000) + 1000000000;

  static Future<void> _initActionNotifications() async {
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
      NotificationChannel(
        channelGroupKey: 'sophie_tasks',
        channelKey: _snoozeChannelKey,
        channelName: 'Task snooze reminders',
        channelDescription: 'Snoozed task reminders',
        importance: NotificationImportance.Max,
        playSound: true,
        enableVibration: true,
        defaultPrivacy: NotificationPrivacy.Public,
      ),
    ]);

    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onNotificationAction,
    );
  }

  static void _startRingingListener() {
    Alarm.ringing.listen(_onRingingChanged);
  }

  static Future<void> _onRingingChanged(AlarmSet alarmSet) async {
    final currentById = <int, AlarmSettings>{
      for (final alarm in alarmSet.alarms) alarm.id: alarm,
    };
    final currentIds = currentById.keys.toSet();

    final startedIds = currentIds.difference(_knownRingingIds);
    final stoppedIds = _knownRingingIds.difference(currentIds);

    await _handleStartedAlarms(startedIds, currentById);
    await _handleStoppedAlarms(stoppedIds);

    _knownRingingIds = currentIds;
  }

  static Future _handleStartedAlarms(
    Set<int> startedIds,
    Map<int, AlarmSettings> currentById,
  ) async {
    for (final alarmId in startedIds) {
      final alarm = currentById[alarmId];
      if (alarm == null) continue;

      final taskId = _taskIdFromPayload(alarm.payload);
      if (taskId == null) continue;

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: _actionNotifId(alarmId),
          channelKey: _actionsChannelKey,
          title: 'Sophie',
          body: alarm.notificationSettings.body,
          payload: {'alarmId': '$alarmId', 'taskId': taskId},
          autoDismissible: false,
          wakeUpScreen: true,
          locked: true,
        ),
        actionButtons: [
          NotificationActionButton(key: _stopActionKey, label: 'Stop'),
          NotificationActionButton(key: _doneActionKey, label: 'Mark done'),
          NotificationActionButton(key: _snoozeActionKey, label: 'Snooze'),
        ],
      );
    }
  }

  static Future _handleStoppedAlarms(Set<int> stoppedIds) async {
    for (final alarmId in stoppedIds) {
      await AwesomeNotifications().dismiss(_actionNotifId(alarmId));
    }
  }

  static String? _taskIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final parsed = jsonDecode(payload);
      if (parsed is Map<String, dynamic>) {
        return parsed['taskId'] as String?;
      }
    } catch (_) {
      // Ignore malformed payloads and fall back to local mapping.
    }
    return null;
  }

  @pragma('vm:entry-point')
  static Future<void> _onNotificationAction(ReceivedAction action) async {
    final alarmId = int.tryParse(action.payload?['alarmId'] ?? '');
    if (alarmId == null) return;

    if (action.buttonKeyPressed == _stopActionKey) {
      try {
        await Alarm.stop(alarmId);
      } catch (_) {}
      await AwesomeNotifications().dismiss(_actionNotifId(alarmId));
      return;
    }

    if (action.buttonKeyPressed == _snoozeActionKey) {
      try {
        await Alarm.stop(alarmId);
      } catch (_) {}
      await AwesomeNotifications().dismiss(_actionNotifId(alarmId));
      await _scheduleSnoozeNotification(
        alarmId,
        action.payload?['taskId'],
        action.body,
      );
      return;
    }

    if (action.buttonKeyPressed == _doneActionKey) {
      try {
        await Alarm.stop(alarmId);
      } catch (_) {}
      await AwesomeNotifications().dismiss(_actionNotifId(alarmId));
      final taskId = action.payload?['taskId'];
      if (taskId != null) {
        await _markTaskDone(taskId);
      }
    }
  }

  static Future<void> _scheduleSnoozeNotification(
    int alarmId,
    String? taskId,
    String? body,
  ) async {
    final fireAt = DateTime.now().add(const Duration(minutes: 15));
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _actionNotifId(alarmId),
        channelKey: _snoozeChannelKey,
        title: 'Sophie',
        body: body,
        payload: {'alarmId': '$alarmId', 'taskId': ?taskId},
        autoDismissible: false,
        wakeUpScreen: true,
        locked: true,
        criticalAlert: true,
        category: NotificationCategory.Alarm,
      ),
      schedule: NotificationCalendar.fromDate(date: fireAt),
      actionButtons: [
        NotificationActionButton(key: _doneActionKey, label: 'Mark done'),
        NotificationActionButton(key: _snoozeActionKey, label: 'Snooze'),
      ],
    );
  }

  static Future<void> _markTaskDone(String taskId) async {
    await Storage.init();
    final serverUrl = Storage.serverUrl;
    final token = Storage.authToken;
    if (serverUrl == null || token == null) return;

    final client = BackendClient(baseUrl: serverUrl, token: token);
    try {
      final cachedTask = Storage.getDashboardData()?.tasks
          .where((t) => t.id == taskId)
          .firstOrNull;
      final next = await client.setTaskDone(taskId: taskId, done: true);
      await cancelForTask(taskId);

      if (next != null && cachedTask != null) {
        // For recurring tasks the backend spawns the next task; we recreate alerts from cache.
        await scheduleForTask(
          Task(
            id: next.nextTaskId,
            text: cachedTask.text,
            dueAt: next.nextDueAt,
            rrule: cachedTask.rrule,
            color: cachedTask.color,
            isOwner: true,
            createdAt: DateTime.now(),
            collaborators: const [],
            alerts: cachedTask.alerts
                .where((a) => a.timeBefore != null)
                .map((a) => TaskAlert(id: 0, timeBefore: a.timeBefore))
                .toList(),
          ),
        );
      }
    } finally {
      client.close();
    }
  }
}
