import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'models.dart';

export 'models.dart';

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class BackendClient {
  static const _timeout = Duration(seconds: 10);
  static const _uploadTimeout = Duration(seconds: 60);

  final String baseUrl;
  final void Function()? onUnauthorized;
  String? _token;

  final _httpClient = http.Client();

  BackendClient({required this.baseUrl, String? token, this.onUnauthorized})
    : _token = token;

  void close() => _httpClient.close();

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
        .get(Uri.parse('$baseUrl/api/dashboard'), headers: _headers)
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

  Future<void> downloadFileTo(String fileId, String destPath) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}'),
    )..headers.addAll(_authHeaders);

    final streamed = await _httpClient.send(request).timeout(_uploadTimeout);

    _checkUnauthorized(streamed.statusCode);
    if (streamed.statusCode == 403) throw Exception('Forbidden');
    if (streamed.statusCode == 404) throw Exception('File not found');
    if (streamed.statusCode != 200) {
      throw Exception('Failed to download file: ${streamed.statusCode}');
    }

    final sink = File(destPath).openWrite();
    try {
      await streamed.stream.pipe(sink);
    } finally {
      await sink.close();
    }
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

  Future<String> createTask({
    required String text,
    String? rrule,
    DateTime? dueAt,
    String? color,
    List<String> collaboratorIds = const [],
    List<({DateTime? alertAt, Duration? timeBefore})> alerts = const [],
  }) async {
    String pad(int n) => n.toString().padLeft(2, '0');
    String durationToTime(Duration d) =>
        '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/tasks'),
          headers: _headers,
          body: jsonEncode({
            'text': text,
            if (rrule != null && rrule.isNotEmpty) 'rrule': rrule,
            if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
            'color': color,
            if (collaboratorIds.isNotEmpty) 'collaboratorIds': collaboratorIds,
            if (alerts.isNotEmpty)
              'alerts': alerts
                  .map(
                    (a) => a.alertAt != null
                        ? {
                            'type': 'absolute',
                            'alertAt': a.alertAt!.toUtc().toIso8601String(),
                          }
                        : {
                            'type': 'relative',
                            'timeBefore': durationToTime(a.timeBefore!),
                          },
                  )
                  .toList(),
          }),
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 201) {
      throw Exception('Failed to create task: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

  Future<void> setTaskDone({required String taskId, required bool done}) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/tasks'),
          headers: _headers,
          body: jsonEncode({'taskId': taskId, 'done': done}),
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }

  Future<void> deleteTask({required String taskId}) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/tasks'),
          headers: _headers,
          body: jsonEncode({'taskId': taskId}),
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  Future<void> updateTask({
    required String taskId,
    required String text,
    String? rrule,
    DateTime? dueAt,
    String? color,
    List<String> collaboratorIds = const [],
    List<({DateTime? alertAt, Duration? timeBefore})> alerts = const [],
  }) async {
    String pad(int n) => n.toString().padLeft(2, '0');
    String durationToTime(Duration d) =>
        '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/tasks'),
          headers: _headers,
          body: jsonEncode({
            'taskId': taskId,
            'text': text,
            if (rrule != null && rrule.isNotEmpty) 'rrule': rrule,
            if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
            'color': color,
            if (collaboratorIds.isNotEmpty) 'collaboratorIds': collaboratorIds,
            'alerts': alerts
                .map(
                  (a) => a.alertAt != null
                      ? {
                          'type': 'absolute',
                          'alertAt': a.alertAt!.toUtc().toIso8601String(),
                        }
                      : {
                          'type': 'relative',
                          'timeBefore': durationToTime(a.timeBefore!),
                        },
                )
                .toList(),
          }),
        )
        .timeout(_timeout);

    _checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }
}
