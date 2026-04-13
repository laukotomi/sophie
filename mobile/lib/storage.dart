import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models.dart';

class Storage {
  static const String authTokenKey = 'auth_token';
  static const String serverUrlKey = 'server_url';
  static const String dashboardCacheKey = 'cached_dashboard';
  static const String _alertCountsKey = 'alert_notif_counts';
  static late SharedPreferences _prefs;

  static String? get authToken => _prefs.getString(authTokenKey);
  static String? get serverUrl => _prefs.getString(serverUrlKey);

  static Future init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveDashboardData(DashboardData data) async {
    await _prefs.setString(dashboardCacheKey, jsonEncode(data.toJson()));
  }

  static Future<void> clear() async {
    await _prefs.remove(authTokenKey);
    await _prefs.remove(dashboardCacheKey);
  }

  static DashboardData? getDashboardData() {
    final raw = _prefs.getString(dashboardCacheKey);
    if (raw == null) return null;
    try {
      return DashboardData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setAuthToken(String token) async {
    await _prefs.setString(authTokenKey, token);
  }

  static Future<void> setServerUrl(String url) async {
    await _prefs.setString(serverUrlKey, url);
  }

  static int getAlertCount(String taskId) {
    final raw = _prefs.getString(_alertCountsKey);
    if (raw == null) return 0;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return (map[taskId] as int?) ?? 0;
  }

  static Future<void> setAlertCount(String taskId, int count) async {
    final raw = _prefs.getString(_alertCountsKey);
    final map = raw != null
        ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
        : <String, dynamic>{};
    map[taskId] = count;
    await _prefs.setString(_alertCountsKey, jsonEncode(map));
  }

  static Future<void> removeAlertCount(String taskId) async {
    final raw = _prefs.getString(_alertCountsKey);
    if (raw == null) return;
    final map = Map<String, dynamic>.from(jsonDecode(raw) as Map)
      ..remove(taskId);
    await _prefs.setString(_alertCountsKey, jsonEncode(map));
  }
}
