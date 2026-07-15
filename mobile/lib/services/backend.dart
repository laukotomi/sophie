import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/backend_note_file.dart';
import 'package:sophie/services/backend_task.dart';

class NotFoundException implements Exception {
  const NotFoundException();
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class BackendClient {
  static const _timeout = Duration(seconds: 10);

  final String baseUrl;
  String? _token;

  BackendClient({required this.baseUrl, String? token}) : _token = token;

  Future _checkUnauthorized(int statusCode) async {
    if (statusCode == 401) {
      await AppEventBus.instance.emit(AppLogoutEvent());
      throw const UnauthorizedException();
    }
  }

  Map<String, String> _getHeaders(bool json) {
    final headers = <String, String>{};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  BackendTask get task => BackendTask(
    baseUrl: baseUrl,
    getHeaders: _getHeaders,
    checkUnauthorized: _checkUnauthorized,
    timeout: _timeout,
  );

  BackendNote get note => BackendNote(
    baseUrl: baseUrl,
    getHeaders: _getHeaders,
    checkUnauthorized: _checkUnauthorized,
    timeout: _timeout,
  );

  BackendNoteFile get noteFile => BackendNoteFile(
    baseUrl: baseUrl,
    getHeaders: _getHeaders,
    checkUnauthorized: _checkUnauthorized,
    timeout: _timeout,
  );

  Future<String> login(String email, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/token'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    await _checkUnauthorized(response.statusCode);
    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _token = json['token'] as String;
    return _token!;
  }

  Future<DashboardData> getDashboardData() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/dashboard'), headers: _getHeaders(false))
        .timeout(_timeout);

    await _checkUnauthorized(response.statusCode);
    if (response.statusCode != 200) {
      throw Exception('Failed to load dashboard data: ${response.statusCode}');
    }

    return DashboardData.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
