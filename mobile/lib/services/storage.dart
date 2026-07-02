import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/pending_note_edit.dart';
import 'package:sophie/services/offline_queue.dart';

class Storage {
  static const String _authTokenKey = 'auth_token';
  static const String _serverUrlKey = 'server_url';
  static const String _dashboardCacheKey = 'cached_dashboard';
  static const String _alertCountsKey = 'alert_notif_counts';
  static const String _snoozePendingKey = 'snooze_pending';
  static const String _offlineNoteEditsKey = 'offline_note_edits';

  static late SharedPreferences _prefs;

  static String? get authToken => _prefs.getString(_authTokenKey);
  static String? get serverUrl => _prefs.getString(_serverUrlKey);

  static Map<String, dynamic> _getAlertCountsMap() {
    final raw = _prefs.getString(_alertCountsKey);
    final map = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    return map;
  }

  static void _saveAlertCountsMap(Map<String, dynamic> map) {
    _prefs.setString(_alertCountsKey, jsonEncode(map));
  }

  static Future init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveDashboardData(DashboardData data) async {
    await _prefs.setString(_dashboardCacheKey, jsonEncode(data.toJson()));
  }

  static Future<void> clear() async {
    await _prefs.remove(_authTokenKey);
    await _prefs.remove(_dashboardCacheKey);
    await _prefs.remove(_alertCountsKey);
    await _prefs.remove(_snoozePendingKey);
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

  static Future<void> setAuthToken(String token) async {
    await _prefs.setString(_authTokenKey, token);
  }

  static Future<void> setServerUrl(String url) async {
    await _prefs.setString(_serverUrlKey, url);
  }

  static int getAlertCount(String taskId) {
    final map = _getAlertCountsMap();
    return (map[taskId] as int?) ?? 0;
  }

  static Future<void> setAlertCount(String taskId, int count) async {
    final map = _getAlertCountsMap();
    map[taskId] = count;
    _saveAlertCountsMap(map);
  }

  static Future<void> removeAlertCount(String taskId) async {
    final map = _getAlertCountsMap()..remove(taskId);
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

  static Future<void> addSnoozePending(
    int alarmId,
    String taskId,
    String? body,
  ) async {
    final list = getSnoozePending();
    list.add({'alarmId': alarmId, 'taskId': taskId, 'body': body});
    await _prefs.setString(_snoozePendingKey, jsonEncode(list));
  }

  static Future<void> removeSnoozePending(int alarmId) async {
    final list = getSnoozePending()
      ..removeWhere((e) => e['alarmId'] == alarmId);
    await _prefs.setString(_snoozePendingKey, jsonEncode(list));
  }

  static Future<Map<String, dynamic>?> popLastSnoozePending() async {
    final list = getSnoozePending();
    if (list.isEmpty) return null;
    final item = list.removeLast();
    await _prefs.setString(_snoozePendingKey, jsonEncode(list));
    return item;
  }

  // ---------------------------------------------------------------------------
  // Offline note edits queue
  // ---------------------------------------------------------------------------
  static Future<List<PendingNoteEdit>> getPendingNoteEdits() async {
    final raw = _prefs.getString(_offlineNoteEditsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PendingNoteEdit.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePendingNoteEdits(List<PendingNoteEdit> edits) async {
    await _prefs.setString(
      _offlineNoteEditsKey,
      jsonEncode(edits.map((e) => e.toJson()).toList()),
    );
  }

  /// Enqueues an edit, replacing any existing pending edit for the same note
  /// so we only ever sync the latest version.
  static Future<void> addPendingNoteEdit(PendingNoteEdit edit) async {
    final list = await getPendingNoteEdits();
    list.removeWhere((e) => e.noteId == edit.noteId);
    list.add(edit);
    await savePendingNoteEdits(list);
  }

  static Future<void> removePendingNoteEdit(String noteId) async {
    final list = await getPendingNoteEdits();
    list.removeWhere((e) => e.noteId == noteId);
    await savePendingNoteEdits(list);
  }
}
