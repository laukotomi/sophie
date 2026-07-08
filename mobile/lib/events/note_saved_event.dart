import 'package:sophie/services/note_events.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class NoteSavedEvent extends NoteEvent {
  late final bool isNew;
  late final String noteId;
  final String text;
  final List<({String userId, String right})> collaborators;
  final int? fixedPosition;
  final String? color;
  final bool dontFold;
  final bool todoList;
  final List<({String path, String name})> files;

  NoteSavedEvent({
    String? noteId,
    required this.text,
    required this.collaborators,
    required this.fixedPosition,
    required this.color,
    required this.dontFold,
    required this.todoList,
    required this.files,
  }) {
    isNew = noteId == null;
    this.noteId = noteId ?? _uuid.v4();
  }

  @override
  String get type => 'note_saved';

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'noteId': noteId,
    'text': text,
    'collaborators': collaborators
        .map((c) => {'userId': c.userId, 'right': c.right})
        .toList(),
    'fixedPosition': fixedPosition,
    'color': color,
    'dontFold': dontFold,
    'todoList': todoList,
    'files': files.map((f) => {'path': f.path, 'name': f.name}).toList(),
  };

  factory NoteSavedEvent.fromJson(Map<String, dynamic> m) => NoteSavedEvent(
    noteId: m['noteId'] as String?,
    text: m['text'] as String,
    collaborators: (m['collaborators'] as List<dynamic>)
        .map(
          (c) => (userId: c['userId'] as String, right: c['right'] as String),
        )
        .toList(),
    fixedPosition: m['fixedPosition'] as int?,
    color: m['color'] as String?,
    dontFold: m['dontFold'] as bool,
    todoList: m['todoList'] as bool,
    files: (m['files'] as List<dynamic>)
        .map((f) => (path: f['path'] as String, name: f['name'] as String))
        .toList(),
  );
}
