import 'package:sophie/main.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/note_events.dart';

class NoteDeletedEvent extends NoteEvent {
  final String noteId;

  NoteDeletedEvent(this.noteId);

  @override
  String get type => 'note_deleted';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'noteId': noteId};

  factory NoteDeletedEvent.fromJson(Map<String, dynamic> m) =>
      NoteDeletedEvent(m['noteId'] as String);

  @override
  Future apply(List<Note> notes, Function setState) async {
    setState(() {
      notes.removeWhere((n) => n.id == noteId);
    });
  }

  @override
  Future sync(List<Note> notes, Function setState) async {
    await getIt<BackendNote>().deleteNote(noteId);
  }
}
