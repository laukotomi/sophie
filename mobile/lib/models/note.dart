import 'package:sophie/models/note_collaborator.dart';
import 'package:sophie/models/note_file.dart';

class Note {
  final String id;
  String text;
  final String? color;
  final bool dontFold;
  final bool todoList;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String right;
  final bool isOwner;
  final String ownerId;
  final int? position;
  final List<NoteCollaborator> collaborators;
  final List<NoteFile> files;

  Note({
    required this.id,
    required this.text,
    this.color,
    this.dontFold = false,
    this.todoList = false,
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
    dontFold: json['dontFold'] as bool? ?? false,
    todoList: json['todoList'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
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
    'dontFold': dontFold,
    'todoList': todoList,
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
