import 'package:sophie/models/task.dart';
import 'package:sophie/services/task_events.dart';

class TaskSetDoneEvent extends TaskEvent {
  final Task task;
  final bool done;

  TaskSetDoneEvent({required this.task, required this.done});

  @override
  String get type => 'task_set_done';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'task': task.toJson(), 'done': done};
  }

  factory TaskSetDoneEvent.fromJson(Map<String, dynamic> m) {
    return TaskSetDoneEvent(
      task: Task.fromJson(m['task'] as Map<String, dynamic>),
      done: m['done'] as bool,
    );
  }
}
