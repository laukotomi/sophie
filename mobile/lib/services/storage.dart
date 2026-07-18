import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/pending_snooze.dart';
import 'package:sophie/models/scheduled_notification.dart';
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

  static String? get authToken => _prefs.getString(_authTokenKey);
  static String? get serverUrl => _prefs.getString(_serverUrlKey);

  static Future init() async {
    _prefs = await SharedPreferences.getInstance();
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

  static Map<String, List<ScheduledNotification>> getTaskAlertsMap() {
    final raw = _prefs.getString(_taskAlertsMapKey);
    final json = raw != null
        ? jsonDecode(raw) as Map<String, dynamic>
        : <String, dynamic>{};

    final map = <String, List<ScheduledNotification>>{};

    for (final entry in json.entries) {
      final taskId = entry.key;
      final list = (entry.value as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(ScheduledNotification.fromJson)
          .toList();

      map[taskId] = list;
    }

    return map;
  }

  static List<ScheduledNotification> getAllScheduledNotifications() {
    final map = getTaskAlertsMap();
    return map.values.expand((list) => list).toList();
  }

  static Future setTaskAlertsMap(
    Map<String, List<ScheduledNotification>> map,
  ) async {
    await _prefs.setString(_taskAlertsMapKey, jsonEncode(map));
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
      final taskId = alert.taskId;
      final taskAlerts = map[taskId];
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

  static Future<PendingSnooze?> tryGetPendingSnooze() async {
    final list = _getSnoozePendings();
    if (list.isEmpty) return null;
    return list[0];
  }

  // ---------------------------------------------------------------------------
  // Offline note events queue
  // ---------------------------------------------------------------------------
  static Future<List<NoteEvent>> getOfflineNoteEvents() async {
    final raw = _prefs.getString(_offlineNoteEventsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(NoteEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future _saveOfflineNoteEvents(List<NoteEvent> events) async {
    await _prefs.setString(
      _offlineNoteEventsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  static Future addNoteEvent(NoteEvent event) async {
    final list = await getOfflineNoteEvents();
    list.add(event);
    await _saveOfflineNoteEvents(list);
  }

  static Future removeNoteEvent(int eventId) async {
    final list = await getOfflineNoteEvents();
    list.removeWhere((e) => e.eventId == eventId);
    await _saveOfflineNoteEvents(list);
  }

  // ---------------------------------------------------------------------------
  // Offline task events queue
  // ---------------------------------------------------------------------------

  static Future<List<TaskEvent>> getOfflineTaskEvents() async {
    final raw = _prefs.getString(_offlineTaskEventsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(TaskEvent.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future _saveOfflineTaskEvents(List<TaskEvent> events) async {
    await _prefs.setString(
      _offlineTaskEventsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  static Future addTaskEvent(TaskEvent event) async {
    final list = await getOfflineTaskEvents();
    list.add(event);
    await _saveOfflineTaskEvents(list);
  }

  static Future removeTaskEvent(int eventId) async {
    final list = await getOfflineTaskEvents();
    list.removeWhere((e) => e.eventId == eventId);
    await _saveOfflineTaskEvents(list);
  }
}
