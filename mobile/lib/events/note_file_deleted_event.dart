import 'package:sophie/services/note_events.dart';

class NoteFileDeletedEvent extends NoteEvent {
  final String fileId;

  NoteFileDeletedEvent({required this.fileId});

  @override
  String get type => 'note_file_deleted';

  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'fileId': fileId};

  factory NoteFileDeletedEvent.fromJson(Map<String, dynamic> m) =>
      NoteFileDeletedEvent(fileId: m['fileId'] as String);
}
