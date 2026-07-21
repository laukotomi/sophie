import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_group_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/events/task_set_done_event.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/storage.dart';

abstract class TaskEvent extends BaseEvent<Task> {
  static TaskEvent fromJson(Map<String, dynamic> json) {
    final event = switch (json['type'] as String) {
      'task_deleted' => TaskDeletedEvent.fromJson(json),
      'task_group_deleted' => TaskGroupDeletedEvent.fromJson(json),
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
  List<TaskEvent> get unappliedEvents => Storage.getOfflineTaskEvents();

  @override
  void saveUnappliedEvent(TaskEvent event) {
    Storage.addOrUpdateTaskEvent(event);
  }
}
