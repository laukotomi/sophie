import 'package:sophie/services/task_events.dart';

class TaskDeletedEvent extends TaskEvent {
  final String taskId;

  TaskDeletedEvent({required this.taskId});

  @override
  String get type => 'task_deleted';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'taskId': taskId};
  }

  factory TaskDeletedEvent.fromJson(Map<String, dynamic> m) {
    return TaskDeletedEvent(taskId: m['taskId'] as String);
  }
}
