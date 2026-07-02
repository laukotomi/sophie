import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/backend_note_file.dart';
import 'package:sophie/services/backend_task.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class BackendClient {
  static const _timeout = Duration(seconds: 10);

  final String baseUrl;
  final void Function()? onUnauthorized;
  String? _token;

  BackendClient({required this.baseUrl, String? token, this.onUnauthorized})
    : _token = token;

  void _checkUnauthorized(int statusCode) {
    if (statusCode == 401) {
      onUnauthorized?.call();
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

    _checkUnauthorized(response.statusCode);
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

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 200) {
      throw Exception('Failed to load dashboard data: ${response.statusCode}');
    }

    return DashboardData.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
