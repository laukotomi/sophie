import 'package:sophie/events/app_sync_conflict_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/models/note_collaborator.dart';
import 'package:sophie/models/note_file.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/services/user_service.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

const _uuid = Uuid();

class NoteSavedEvent extends NoteEvent {
  late final bool isNew;
  late final String noteId;
  bool skipConflictCheck = false;
  final String text;
  final List<({String userId, String right})> collaborators;
  final int? fixedPosition;
  final String? color;
  final bool dontFold;
  final bool todoList;
  final List<({String id, String path, String name})> newFiles;
  final bool hasLockAlready;

  NoteSavedEvent({
    String? noteId,
    required this.text,
    required this.collaborators,
    required this.fixedPosition,
    required this.color,
    required this.dontFold,
    required this.todoList,
    required this.newFiles,
    this.hasLockAlready = false,
    bool? isNew,
  }) {
    this.isNew = isNew ?? noteId == null;
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
    'newFiles': newFiles
        .map((f) => {'id': f.id, 'path': f.path, 'name': f.name})
        .toList(),
    'isNew': isNew,
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
    newFiles: (m['newFiles'] as List<dynamic>)
        .map(
          (f) => (
            id: f['id'] as String,
            path: f['path'] as String,
            name: f['name'] as String,
          ),
        )
        .toList(),
    isNew: m['isNew'] as bool,
  );

  @override
  Future apply(List<Note> notes, Function setState) async {
    final users = getIt<UserService>().users;
    final collabs = collaborators.map((c) {
      final user = users.firstWhere((u) => u.id == c.userId);
      return NoteCollaborator(
        id: user.id,
        email: user.email,
        name: user.name,
        right: c.right,
      );
    }).toList();

    final newFiles = this.newFiles
        .map((f) => NoteFile(id: f.id, fileName: f.name))
        .toList();

    if (!isNew) {
      final note = notes.firstWhereOrNull((n) => n.id == noteId);
      if (note == null) {
        return;
      }

      setState(() {
        note
          ..updatedAt = DateTime.now()
          ..position = fixedPosition
          ..text = text
          ..color = color
          ..dontFold = dontFold
          ..todoList = todoList
          ..collaborators = collabs
          ..files.addAll(newFiles);
      });
    } else {
      final ownerId = getIt<UserService>().currentUserId;
      setState(() {
        notes.add(
          Note(
            collaborators: collabs,
            createdAt: DateTime.now(),
            id: noteId,
            isOwner: true,
            ownerId: ownerId,
            right: 'owner',
            text: text,
            updatedAt: DateTime.now(),
            color: color,
            dontFold: dontFold,
            position: fixedPosition,
            todoList: todoList,
            files: newFiles,
          ),
        );
      });
    }

    setState(() {
      notes.sort((a, b) {
        final posA = a.position;
        final posB = b.position;
        if (posA != null && posB != null) return posA.compareTo(posB);
        if (posA != null) return -1;
        if (posB != null) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    });
  }

  @override
  Future sync(List<Note> notes, Function setState) async {
    final noteClient = getIt<BackendNote>();
    bool hadConflict = false;

    if (!isNew && !hasLockAlready) {
      final result = await noteClient.acquireNoteLock(noteId);
      hadConflict = !skipConflictCheck && createdAt.isBefore(result.updatedAt);
    }

    await noteClient.saveNote(this);

    if (hadConflict) {
      await AppEventBus.instance.emit(AppSyncConflictEvent());
    }
  }
}
