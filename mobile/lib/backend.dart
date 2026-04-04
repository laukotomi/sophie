import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

export 'models.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class BackendClient {
  static const _timeout = Duration(seconds: 5);
  static const _uploadTimeout = Duration(seconds: 30);

  final String baseUrl;
  final void Function()? onUnauthorized;
  String? _token;

  BackendClient({required this.baseUrl, String? token, this.onUnauthorized})
    : _token = token;

  Map<String, String> get _headers => {
    if (_token != null) 'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _authHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  void _checkUnauthorized(int statusCode) {
    if (statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }
  }

  Future<http.MultipartRequest> _buildNoteRequest(
    String method, {
    String? noteId,
    required String text,
    required List<({String userId, String right})> collaborators,
    int? fixedPosition,
    String? color,
    required List<({String path, String name})> files,
  }) async {
    final request =
        http.MultipartRequest(method, Uri.parse('$baseUrl/api/notes'))
          ..headers.addAll(_authHeaders)
          ..fields['text'] = text;
    if (noteId != null) request.fields['noteId'] = noteId;
    if (collaborators.isNotEmpty) {
      request.fields['collaborators'] = jsonEncode(
        collaborators
            .map((c) => {'userId': c.userId, 'right': c.right})
            .toList(),
      );
    }
    if (fixedPosition != null) {
      request.fields['fixedPosition'] = fixedPosition.toString();
    }
    if (color != null) {
      request.fields['color'] = color;
    }
    for (final file in files) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: file.name,
        ),
      );
    }
    return request;
  }

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
        .get(Uri.parse('$baseUrl/api/notes'), headers: _headers)
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 200) {
      throw Exception('Failed to load dashboard data: ${response.statusCode}');
    }

    return DashboardData.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> createNote(
    String text, {
    List<({String userId, String right})> collaborators = const [],
    int? fixedPosition,
    String? color,
    List<({String path, String name})> files = const [],
  }) async {
    final request = await _buildNoteRequest(
      'POST',
      text: text,
      collaborators: collaborators,
      fixedPosition: fixedPosition,
      color: color,
      files: files,
    );
    final response = await http.Response.fromStream(
      await request.send().timeout(_timeout),
    );

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 201) {
      throw Exception('Failed to create note: ${response.statusCode}');
    }
  }

  Future<void> updateNote(
    String noteId,
    String text, {
    List<({String userId, String right})> collaborators = const [],
    int? fixedPosition,
    String? color,
    List<({String path, String name})> files = const [],
  }) async {
    final request = await _buildNoteRequest(
      'PUT',
      noteId: noteId,
      text: text,
      collaborators: collaborators,
      fixedPosition: fixedPosition,
      color: color,
      files: files,
    );
    final response = await http.Response.fromStream(
      await request.send().timeout(_timeout),
    );

    _checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
    if (response.statusCode != 204) {
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final response = await http
        .get(
          Uri.parse(
            '$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}',
          ),
          headers: _authHeaders,
        )
        .timeout(_uploadTimeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('File not found');
    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  Future<void> deleteFile(String fileId) async {
    final response = await http
        .delete(
          Uri.parse(
            '$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}',
          ),
          headers: _authHeaders,
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('File not found');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete file: ${response.statusCode}');
    }
  }

  Future<void> deleteNote(String noteId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/notes'),
          headers: _headers,
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }
}
