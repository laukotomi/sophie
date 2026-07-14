import 'dart:async';

import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/events/task_set_done_event.dart';

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
      'task_set_done' => TaskSetDoneEvent.fromJson(json),
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

  final _handlers = <Future Function(TaskEvent)>[];

  TaskEventSubscription listen(Future Function(TaskEvent) handler) {
    _handlers.add(handler);
    return TaskEventSubscription._(_handlers, handler);
  }

  Future emit(TaskEvent event) async {
    await Future.wait(_handlers.map((h) => h(event)));
  }
}

class TaskEventSubscription {
  final List<Future Function(TaskEvent)> _handlers;
  final Future Function(TaskEvent) _handler;

  TaskEventSubscription._(this._handlers, this._handler);

  void cancel() => _handlers.remove(_handler);
}
