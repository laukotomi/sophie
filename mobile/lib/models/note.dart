import 'package:sophie/models/base_entity.dart';
import 'package:sophie/models/note_collaborator.dart';
import 'package:sophie/models/note_file.dart';

class Note extends BaseEntity {
  String text;
  String? color;
  bool dontFold;
  bool todoList;
  final String right;
  final bool isOwner;
  final String ownerId;
  int? position;
  List<NoteCollaborator> collaborators;
  final List<NoteFile> files;
  bool hasConflict = false;

  Note({
    required this.text,
    this.color,
    this.dontFold = false,
    this.todoList = false,
    required this.right,
    required this.isOwner,
    required this.ownerId,
    this.position,
    required this.collaborators,
    required this.files,
    required super.id,
    required super.createdAt,
    required super.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    final baseFields = BaseEntity.parseBaseFields(json);

    return Note(
      id: baseFields.id,
      text: json['text'] as String,
      color: json['color'] as String?,
      dontFold: json['dontFold'] as bool? ?? false,
      todoList: json['todoList'] as bool? ?? false,
      createdAt: baseFields.createdAt,
      updatedAt: baseFields.updatedAt,
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
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'text': text,
    'color': color,
    'dontFold': dontFold,
    'todoList': todoList,
    'right': right,
    'isOwner': isOwner,
    'ownerId': ownerId,
    'position': position,
    'collaborators': collaborators.map((c) => c.toJson()).toList(),
    'files': files.map((f) => f.toJson()).toList(),
  };
}
