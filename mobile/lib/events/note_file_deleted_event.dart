import 'package:sophie/main.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/services/backend_note_file.dart';
import 'package:sophie/services/note_events.dart';

class NoteFileDeletedEvent extends NoteEvent {
  final String noteId;
  final String? fileId;

  NoteFileDeletedEvent({required this.noteId, this.fileId});

  @override
  String get type => 'note_file_deleted';

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'noteId': noteId,
    'fileId': fileId,
  };

  factory NoteFileDeletedEvent.fromJson(Map<String, dynamic> m) =>
      NoteFileDeletedEvent(
        noteId: m['noteId'] as String,
        fileId: m['fileId'] as String?,
      );

  @override
  Future apply(List<Note> notes, Function setState) async {
    final note = notes.firstWhere((n) => n.id == noteId);
    setState(() {
      note.files.removeWhere((f) => f.id == fileId);
    });
  }

  @override
  Future sync(List<Note> notes, Function setState) async {
    await getIt<BackendNoteFile>().deleteFile(fileId!);
  }
}
