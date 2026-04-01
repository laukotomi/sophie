import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String id;
  final String name;
  final String email;

  const AppUser({required this.id, required this.name, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class NoteAlert {
  final String id;
  final String noteId;
  final String time;

  const NoteAlert({required this.id, required this.noteId, required this.time});

  factory NoteAlert.fromJson(Map<String, dynamic> json) => NoteAlert(
    id: json['id'] as String,
    noteId: json['noteId'] as String,
    time: json['time'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'noteId': noteId, 'time': time};
}

class NoteFile {
  final String id;
  final String fileName;
  final int fileSize;
  final DateTime createdAt;

  const NoteFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
  });

  factory NoteFile.fromJson(Map<String, dynamic> json) => NoteFile(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    fileSize: json['fileSize'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'fileSize': fileSize,
    'createdAt': createdAt.toIso8601String(),
  };
}

class NoteCollaborator {
  final String id;
  final String name;
  final String email;
  final String right;

  const NoteCollaborator({
    required this.id,
    required this.name,
    required this.email,
    required this.right,
  });

  factory NoteCollaborator.fromJson(Map<String, dynamic> json) =>
      NoteCollaborator(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        right: json['right'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'right': right,
  };
}

class Note {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String right;
  final bool isOwner;
  final String ownerId;
  final int? position;
  final List<NoteAlert> alerts;
  final List<NoteCollaborator> collaborators;
  final List<NoteFile> files;

  const Note({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.right,
    required this.isOwner,
    required this.ownerId,
    this.position,
    required this.alerts,
    required this.collaborators,
    required this.files,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    right: json['right'] as String,
    isOwner: json['isOwner'] as bool,
    ownerId: json['ownerId'] as String,
    position: json['position'] as int?,
    alerts: (json['alerts'] as List<dynamic>)
        .map((a) => NoteAlert.fromJson(a as Map<String, dynamic>))
        .toList(),
    collaborators: (json['collaborators'] as List<dynamic>)
        .map((c) => NoteCollaborator.fromJson(c as Map<String, dynamic>))
        .toList(),
    files: (json['files'] as List<dynamic>? ?? [])
        .map((f) => NoteFile.fromJson(f as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'right': right,
    'isOwner': isOwner,
    'ownerId': ownerId,
    'position': position,
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'collaborators': collaborators.map((c) => c.toJson()).toList(),
    'files': files.map((f) => f.toJson()).toList(),
  };
}

class DashboardData {
  final AppUser user;
  final List<AppUser> users;
  final List<Note> notes;

  const DashboardData({
    required this.user,
    required this.users,
    required this.notes,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    users: (json['users'] as List<dynamic>)
        .map((u) => AppUser.fromJson(u as Map<String, dynamic>))
        .toList(),
    notes: (json['notes'] as List<dynamic>)
        .map((n) => Note.fromJson(n as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'users': users.map((u) => u.toJson()).toList(),
    'notes': notes.map((n) => n.toJson()).toList(),
  };
}

class DashboardCache {
  static const _key = 'cached_dashboard';

  static Future<void> save(DashboardData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  static Future<DashboardData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return DashboardData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

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

  /// Signs in with email and password and stores the returned bearer token.
  /// Returns the token so callers can persist it.
  Future<String> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/api/token');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _token = json['token'] as String;
    return _token!;
  }

  Future<DashboardData> getDashboardData() async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final response = await http.get(uri, headers: _headers).timeout(_timeout);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to load dashboard data: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DashboardData.fromJson(json);
  }

  Future<void> createNote(
    String text, {
    List<({String userId, String right})> collaborators = const [],
    int? fixedPosition,
    List<({String path, String name})> files = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders)
      ..fields['text'] = text;
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
    for (final file in files) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: file.name,
        ),
      );
    }

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode != 201) {
      throw Exception('Failed to create note: ${response.statusCode}');
    }
  }

  Future<void> updateNote(
    String noteId,
    String text, {
    List<({String userId, String right})> collaborators = const [],
    int? fixedPosition,
    List<({String path, String name})> files = const [],
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final request = http.MultipartRequest('PUT', uri)
      ..headers.addAll(_authHeaders)
      ..fields['noteId'] = noteId
      ..fields['text'] = text;
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
    for (final file in files) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: file.name,
        ),
      );
    }

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode == 403) {
      throw Exception('Forbidden');
    }

    if (response.statusCode == 404) {
      throw Exception('Note not found');
    }

    if (response.statusCode != 204) {
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final uri = Uri.parse(
      '$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}',
    );
    final response = await http
        .get(uri, headers: _authHeaders)
        .timeout(_uploadTimeout);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('File not found');

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: \${response.statusCode}');
    }

    return response.bodyBytes;
  }

  Future<void> deleteFile(String fileId) async {
    final uri = Uri.parse(
      '$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}',
    );
    final response = await http
        .delete(uri, headers: _authHeaders)
        .timeout(_timeout);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('File not found');

    if (response.statusCode != 204) {
      throw Exception('Failed to delete file: \${response.statusCode}');
    }
  }

  Future<void> deleteNote(String noteId) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final response = await http
        .delete(uri, headers: _headers, body: jsonEncode({'noteId': noteId}))
        .timeout(_timeout);

    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }

    if (response.statusCode == 403) {
      throw Exception('Forbidden');
    }

    if (response.statusCode == 404) {
      throw Exception('Note not found');
    }

    if (response.statusCode != 204) {
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }
}
