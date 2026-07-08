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
}
