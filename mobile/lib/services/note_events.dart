import 'dart:async';

import 'package:sophie/events/note_deleted_event.dart';
import 'package:sophie/events/note_file_deleted_event.dart';
import 'package:sophie/events/note_saved_event.dart';

abstract class NoteEvent {
  DateTime createdAt = DateTime.now();
  int get eventId => createdAt.millisecondsSinceEpoch;

  String get type;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'type': type,
  };

  static NoteEvent fromJson(Map<String, dynamic> json) {
    final event = switch (json['type'] as String) {
      'note_saved' => NoteSavedEvent.fromJson(json),
      'note_deleted' => NoteDeletedEvent.fromJson(json),
      'note_file_deleted' => NoteFileDeletedEvent.fromJson(json),
      _ => throw ArgumentError('Unknown event type: ${json['type']}'),
    };

    if (json['createdAt'] != null) {
      event.createdAt = DateTime.parse(json['createdAt'] as String);
    }
    return event;
  }
}

class NoteEventBus {
  static final NoteEventBus instance = NoteEventBus._();
  NoteEventBus._();

  final _handlers = <Future Function(NoteEvent)>[];

  NoteEventSubscription listen(Future Function(NoteEvent) handler) {
    _handlers.add(handler);
    return NoteEventSubscription._(_handlers, handler);
  }

  Future emit(NoteEvent event) async {
    await Future.wait(_handlers.map((h) => h(event)));
  }
}

class NoteEventSubscription {
  final List<Future Function(NoteEvent)> _handlers;
  final Future Function(NoteEvent) _handler;

  NoteEventSubscription._(this._handlers, this._handler);

  void cancel() => _handlers.remove(_handler);
}
