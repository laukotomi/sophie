import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sophie/models.dart';
import 'package:sophie/services/notifications_plugin.dart';
import 'package:sophie/storage.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Manages scheduling of task alert notifications.
///
/// Lifecycle:
/// 1. Call [init] once from [main] — safe with no Activity.
/// 2. Call [requestPermissions] from a widget's [State.initState] — requires
///    a live Activity for the permission dialog.
/// 3. Call [scheduleForTask] after every task create / update.
/// 4. Call [cancelForTask] after a task is deleted.
class AlertNotifications {
  static const _channelId = 'task_alerts_v4';
  static const _channelName = 'Task Alerts';
  static const _channelDesc = 'Task alert reminders';

  /// [alarmClock] uses AlarmManager.setAlarmClock(): exact timing, bypasses
  /// DND "alarms-only" mode, routes to alarm audio stream.
  /// Starts as [inexactAllowWhileIdle] and is upgraded once permissions allow.
  static AndroidScheduleMode _scheduleMode =
      AndroidScheduleMode.inexactAllowWhileIdle;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initialises timezone and the notifications plugin.
  /// Safe to call from [main] before [runApp] — no Android Activity needed.
  static Future<void> init() async {
    // Configure local timezone so TZDateTime fires at the right wall-clock time.
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

    await initNotificationsPlugin();

    // If USE_EXACT_ALARM was auto-granted (API 33+ with the manifest entry),
    // upgrade the schedule mode immediately.
    final canExact =
        await sharedNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    if (canExact) {
      _scheduleMode = AndroidScheduleMode.alarmClock;
    }
  }

  /// Requests POST_NOTIFICATIONS and exact-alarm permissions from the user.
  /// Must be called from a widget [State.initState] or later — requires an
  /// active Android Activity. Never call before [runApp].
  static Future<void> requestPermissions() async {
    final android = sharedNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.requestNotificationsPermission();

    // Only prompt for exact-alarm permission if not already granted.
    final canExact = await android.canScheduleExactNotifications() ?? false;
    if (!canExact) {
      await android.requestExactAlarmsPermission();
    }

    final canExactNow = await android.canScheduleExactNotifications() ?? false;
    _scheduleMode = canExactNow
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.inexactAllowWhileIdle;
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
      await sharedNotificationsPlugin.zonedSchedule(
        id: id,
        title: task.text,
        body: null,
        scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.max,
            // Route audio through the alarm stream: plays at alarm volume and
            // respects "alarms only" DND mode (but not full silent mode).
            audioAttributesUsage: AudioAttributesUsage.alarm,
            sound: RawResourceAndroidNotificationSound('task_alert'),
            // Show on the lock screen without requiring unlock.
            fullScreenIntent: true,
          ),
        ),
        androidScheduleMode: _scheduleMode,
      );
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
      await sharedNotificationsPlugin.cancel(id: _notifId(taskId, i));
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
