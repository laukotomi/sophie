import 'dart:convert';
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
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String right;
  final bool isOwner;
  final String ownerId;
  final int? position;
  final List<NoteCollaborator> collaborators;
  final List<NoteFile> files;

  const Note({
    required this.id,
    required this.text,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.right,
    required this.isOwner,
    required this.ownerId,
    this.position,
    required this.collaborators,
    required this.files,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    text: json['text'] as String,
    color: json['color'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    right: json['right'] as String,
    isOwner: json['isOwner'] as bool,
    ownerId: json['ownerId'] as String,
    position: json['position'] as int?,
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
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'right': right,
    'isOwner': isOwner,
    'ownerId': ownerId,
    'position': position,
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
