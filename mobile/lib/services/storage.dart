import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/services/task_events.dart';

class Storage {
  static const String _authTokenKey = 'auth_token';
  static const String _serverUrlKey = 'server_url';
  static const String _dashboardCacheKey = 'cached_dashboard';
  static const String _alertCountsKey = 'alert_notif_counts';
  static const String _snoozePendingKey = 'snooze_pending';
  static const String _offlineNoteEventsKey = 'offline_note_events';
  static const String _offlineTaskEventsKey = 'offline_task_events';

  static late SharedPreferences _prefs;

  static String? get authToken => _prefs.getString(_authTokenKey);
  static String? get serverUrl => _prefs.getString(_serverUrlKey);

  static Map<String, int> getAlertCountsMap() {
    final raw = _prefs.getString(_alertCountsKey);
    final map = raw != null
        ? Map<String, int>.from(jsonDecode(raw) as Map)
        : <String, int>{};
    return map;
  }

  static void _saveAlertCountsMap(Map<String, int> map) {
    _prefs.setString(_alertCountsKey, jsonEncode(map));
  }

  static Future init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future saveDashboardData(DashboardData data) async {
    await _prefs.setString(_dashboardCacheKey, jsonEncode(data.toJson()));
  }

  static Future clear() async {
    await _prefs.remove(_authTokenKey);
    await _prefs.remove(_dashboardCacheKey);
    await _prefs.remove(_alertCountsKey);
    await _prefs.remove(_snoozePendingKey);
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

  static int getAlertCount(String taskId) {
    final map = getAlertCountsMap();
    return (map[taskId]) ?? 0;
  }

  static Future setAlertCount(String taskId, int count) async {
    final map = getAlertCountsMap();
    map[taskId] = count;
    _saveAlertCountsMap(map);
  }

  static Future removeAlertCount(String taskId) async {
    final map = getAlertCountsMap()..remove(taskId);
    _saveAlertCountsMap(map);
  }

  // ---------------------------------------------------------------------------
  // Snooze pending queue
  // ---------------------------------------------------------------------------

  static List<Map<String, dynamic>> getSnoozePending() {
    final raw = _prefs.getString(_snoozePendingKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future saveSnoozePendingList(List<Map<String, dynamic>> list) async {
    await _prefs.setString(_snoozePendingKey, jsonEncode(list));
  }

  static Future addSnoozePending(
    int alarmId,
    String taskId,
    String? body,
  ) async {
    final list = getSnoozePending();
    list.add({'alarmId': alarmId, 'taskId': taskId, 'body': body});
    await saveSnoozePendingList(list);
  }

  static Future removeSnoozePending(int alarmId) async {
    final list = getSnoozePending()
      ..removeWhere((e) => e['alarmId'] == alarmId);
    await saveSnoozePendingList(list);
  }

  static Future<Map<String, dynamic>?> popLastSnoozePending() async {
    final list = getSnoozePending();
    if (list.isEmpty) return null;
    final item = list.removeLast();
    await saveSnoozePendingList(list);
    return item;
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
