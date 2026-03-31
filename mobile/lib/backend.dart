import 'dart:convert';
import 'package:http/http.dart' as http;

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
  );
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
}

class UnauthorizedException implements Exception {
  const UnauthorizedException();
}

class BackendClient {
  final String baseUrl;
  final void Function()? onUnauthorized;
  String? _token;

  BackendClient({required this.baseUrl, String? token, this.onUnauthorized})
    : _token = token;

  Map<String, String> get _headers => {
    if (_token != null) 'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
  };

  /// Signs in with email and password and stores the returned bearer token.
  /// Returns the token so callers can persist it.
  Future<String> login(String email, String password) async {
    final uri = Uri.parse('$baseUrl/api/token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

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
    final response = await http.get(uri, headers: _headers);

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
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'text': text,
        if (collaborators.isNotEmpty)
          'collaborators': collaborators
              .map((c) => {'userId': c.userId, 'right': c.right})
              .toList(),
        if (fixedPosition != null) 'fixedPosition': fixedPosition,
      }),
    );

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
  }) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final response = await http.put(
      uri,
      headers: _headers,
      body: jsonEncode({
        'noteId': noteId,
        'text': text,
        if (collaborators.isNotEmpty)
          'collaborators': collaborators
              .map((c) => {'userId': c.userId, 'right': c.right})
              .toList(),
        if (fixedPosition != null) 'fixedPosition': fixedPosition,
      }),
    );

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

  Future<void> deleteNote(String noteId) async {
    final uri = Uri.parse('$baseUrl/api/notes');
    final response = await http.delete(
      uri,
      headers: _headers,
      body: jsonEncode({'noteId': noteId}),
    );

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
