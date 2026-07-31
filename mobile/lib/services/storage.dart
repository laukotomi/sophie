import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/pending_snooze.dart';
import 'package:sophie/models/scheduled_notification.dart';
import 'package:sophie/models/settings.dart';
import 'package:sophie/services/event_storage.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/services/task_events.dart';

class Storage {
  static const String _authTokenKey = 'auth_token';
  static const String _serverUrlKey = 'server_url';
  static const String _dashboardCacheKey = 'cached_dashboard';
  static const String _taskAlertsMapKey = 'task_alerts_map';
  static const String _snoozePendingKey = 'snooze_pending';
  static const String _mutedUntilKey = 'muted_until';
  static const String _offlineNoteEventsKey = 'offline_note_events';
  static const String _offlineTaskEventsKey = 'offline_task_events';

  static late SharedPreferences _prefs;
  static late EventStorage<NoteEvent> noteEvents;
  static late EventStorage<TaskEvent> taskEvents;

  static String? get authToken => _prefs.getString(_authTokenKey);
  static String? get serverUrl => _prefs.getString(_serverUrlKey);

  static Future init() async {
    _prefs = await SharedPreferences.getInstance();

    noteEvents = EventStorage<NoteEvent>(
      _prefs,
      _offlineNoteEventsKey,
      (map) => NoteEvent.fromJson(map),
    );

    taskEvents = EventStorage<TaskEvent>(
      _prefs,
      _offlineTaskEventsKey,
      (map) => TaskEvent.fromJson(map),
    );
  }

  static Future saveDashboardData(DashboardData data) async {
    await _prefs.setString(_dashboardCacheKey, jsonEncode(data.toJson()));
  }

  static Future clear() async {
    await _prefs.remove(_authTokenKey);
    await _prefs.remove(_dashboardCacheKey);
    await _prefs.remove(_taskAlertsMapKey);
    await _prefs.remove(_snoozePendingKey);
    await _prefs.remove(_mutedUntilKey);
    await _prefs.remove(_offlineNoteEventsKey);
    await _prefs.remove(_offlineTaskEventsKey);
  }

  static DashboardData? getDashboardData() {
    final raw = _prefs.getString(_dashboardCacheKey);
    if (raw == null) return null;
    try {
      return DashboardData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future setAuthToken(String token) async {
    await _prefs.setString(_authTokenKey, token);
  }

  static Future setServerUrl(String url) async {
    await _prefs.setString(_serverUrlKey, url);
  }

  /////////////////////////////////////////////////////////////////////////////
  // Task alerts
  /////////////////////////////////////////////////////////////////////////////

  static Map<String, List<ScheduledNotification>> getTaskAlertsMap() {
    final raw = _prefs.getString(_taskAlertsMapKey);
    if (raw == null) return {};

    final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);

    return decoded.map(
      (taskId, value) => MapEntry(
        taskId,
        (value as List)
            .cast<Map<String, dynamic>>()
            .map(ScheduledNotification.fromJson)
            .toList(),
      ),
    );
  }

  static Future setTaskAlertsMap(
    Map<String, List<ScheduledNotification>> map,
  ) async {
    await _prefs.setString(_taskAlertsMapKey, jsonEncode(map));
  }

  static List<ScheduledNotification> getAllScheduledNotifications() {
    final map = getTaskAlertsMap();
    return map.values.expand((list) => list).toList();
  }

  static List<ScheduledNotification> getTaskAlerts(String taskId) {
    final map = getTaskAlertsMap();
    return map[taskId] ?? [];
  }

  static Future setTaskAlerts(
    String taskId,
    List<ScheduledNotification> alerts,
  ) async {
    final map = getTaskAlertsMap();
    map[taskId] = alerts;
    await setTaskAlertsMap(map);
  }

  static Future updateTaskAlerts(List<ScheduledNotification> alerts) async {
    final map = getTaskAlertsMap();

    for (final alert in alerts) {
      final taskAlerts = map[alert.taskId];
      if (taskAlerts == null) continue;

      final index = taskAlerts.indexWhere((e) => e.id == alert.id);
      if (index == -1) continue;
      taskAlerts[index] = alert;
    }

    await setTaskAlertsMap(map);
  }

  static Future removeTaskAlerts(String taskId) async {
    final map = getTaskAlertsMap()..remove(taskId);
    await setTaskAlertsMap(map);
  }

  static Future removeTaskAlert(String taskId, int alarmId) async {
    final map = getTaskAlertsMap();
    final alerts = map[taskId];

    if (alerts == null) return;

    alerts.removeWhere((e) => e.id == alarmId);

    if (alerts.isEmpty) {
      map.remove(taskId);
    }
    await setTaskAlertsMap(map);
  }

  // ---------------------------------------------------------------------------
  // Mute
  // ---------------------------------------------------------------------------

  /// Returns the muted-until time, or null if not muted / already expired.
  static DateTime? get mutedUntil {
    final s = _prefs.getString(_mutedUntilKey);
    if (s == null) return null;
    try {
      final dt = DateTime.parse(s);
      return dt.isAfter(DateTime.now()) ? dt : null;
    } catch (_) {
      return null;
    }
  }

  static Future setMutedUntil(DateTime until) async {
    await _prefs.setString(_mutedUntilKey, until.toIso8601String());
  }

  static Future clearMutedUntil() async {
    await _prefs.remove(_mutedUntilKey);
  }

  // ---------------------------------------------------------------------------
  // Snooze pending queue
  // ---------------------------------------------------------------------------

  static List<PendingSnooze> _getSnoozePendings() {
    final raw = _prefs.getString(_snoozePendingKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PendingSnooze.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future _saveSnoozePendingList(List<PendingSnooze> list) async {
    await _prefs.setString(
      _snoozePendingKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  static Future addSnoozePending(
    int alarmId,
    String taskId,
    String body,
  ) async {
    final list = _getSnoozePendings()
      ..add(PendingSnooze(alarmId: alarmId, taskId: taskId, body: body));
    await _saveSnoozePendingList(list);
  }

  static Future removeSnoozePending(int alarmId) async {
    final list = _getSnoozePendings()..removeWhere((e) => e.alarmId == alarmId);
    await _saveSnoozePendingList(list);
  }

  static PendingSnooze? tryGetPendingSnooze() {
    final list = _getSnoozePendings();
    if (list.isEmpty) return null;
    return list[0];
  }

  ///////////////////////////////////////////////////////////////////////////////
  /// Settings
  ///////////////////////////////////////////////////////////////////////////////
  static Future setSettings(Settings settings) async {
    await _prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  static Settings? getSettings() {
    final raw = _prefs.getString('settings');
    if (raw == null) return null;
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
