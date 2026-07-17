import 'dart:async';

import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/events/task_set_done_event.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/storage.dart';

abstract class TaskEvent extends BaseEvent<Task> {
  static TaskEvent fromJson(Map<String, dynamic> json) {
    final event = switch (json['type'] as String) {
      'task_deleted' => TaskDeletedEvent.fromJson(json),
      'task_saved' => TaskSavedEvent.fromJson(json),
      'task_set_done' => TaskSetDoneEvent.fromJson(json),
      _ => throw ArgumentError('Unknown event type: ${json['type']}'),
    };

    BaseEvent.fromJson(event, json);
    return event;
  }
}

class TaskEventBus extends BaseEventBus<TaskEvent> {
  static final TaskEventBus instance = TaskEventBus._();
  TaskEventBus._();

  @override
  Future emit(TaskEvent event) async {
    await super.emit(event);
    if (!event.synced) {
      await Storage.addTaskEvent(event);
    }
  }
}
