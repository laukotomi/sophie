import 'package:sophie/services/task_events.dart';

class TaskToggleDoneEvent extends TaskEvent {
  final int taskId;

  TaskToggleDoneEvent({required this.taskId});

  @override
  String get type => 'task_toggle_done';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'taskId': taskId};
  }

  factory TaskToggleDoneEvent.fromJson(Map<String, dynamic> m) {
    return TaskToggleDoneEvent(taskId: m['taskId'] as int);
  }
}
