import 'dart:async';

import 'package:sophie/events/note_deleted_event.dart';
import 'package:sophie/events/note_file_deleted_event.dart';
import 'package:sophie/events/note_saved_event.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/storage.dart';

abstract class NoteEvent extends BaseEvent<Note> {
  static NoteEvent fromJson(Map<String, dynamic> json) {
    final event = switch (json['type'] as String) {
      'note_saved' => NoteSavedEvent.fromJson(json),
      'note_deleted' => NoteDeletedEvent.fromJson(json),
      'note_file_deleted' => NoteFileDeletedEvent.fromJson(json),
      _ => throw ArgumentError('Unknown event type: ${json['type']}'),
    };

    BaseEvent.fromJson(event, json);
    return event;
  }
}

class NoteEventBus extends BaseEventBus<NoteEvent> {
  static final NoteEventBus instance = NoteEventBus._();
  NoteEventBus._();

  @override
  Future emit(NoteEvent event) async {
    super.emit(event);
    if (!event.synced) {
      await Storage.addNoteEvent(event);
    }
  }
}
