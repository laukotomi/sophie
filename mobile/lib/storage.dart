import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/models.dart';

class Storage {
  static const String authTokenKey = 'auth_token';
  static const String serverUrlKey = 'server_url';
  static const String dashboardCacheKey = 'cached_dashboard';
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
}
