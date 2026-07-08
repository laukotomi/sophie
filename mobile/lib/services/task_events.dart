import 'dart:async';

import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/events/task_toggle_done_event.dart';

abstract class TaskEvent {
  DateTime createdAt = DateTime.now();
  int get eventId => createdAt.millisecondsSinceEpoch;

  String get type;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'type': type,
  };

  static TaskEvent fromJson(Map<String, dynamic> json) {
    final event = switch (json['type'] as String) {
      'task_deleted' => TaskDeletedEvent.fromJson(json),
      'task_saved' => TaskSavedEvent.fromJson(json),
      'task_toggle_done' => TaskToggleDoneEvent.fromJson(json),
      _ => throw ArgumentError('Unknown event type: ${json['type']}'),
    };

    if (json['createdAt'] != null) {
      event.createdAt = DateTime.parse(json['createdAt'] as String);
    }
    return event;
  }
}

class TaskEventBus {
  static final TaskEventBus instance = TaskEventBus._();
  TaskEventBus._();

  final _controller = StreamController<TaskEvent>.broadcast();
  Stream<TaskEvent> get stream => _controller.stream;
  void emit(TaskEvent event) => _controller.add(event);
}
