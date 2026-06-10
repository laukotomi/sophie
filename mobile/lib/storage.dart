import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models.dart';

class Storage {
  static const String _authTokenKey = 'auth_token';
  static const String _serverUrlKey = 'server_url';
  static const String _dashboardCacheKey = 'cached_dashboard';
  static const String _alertCountsKey = 'alert_notif_counts';
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
}
