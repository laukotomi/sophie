import 'package:sophie/main.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/backend_task.dart';
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

  @override
  Future apply(List<Task> tasks, Function setState) async {
    setState(() {
      tasks.removeWhere((t) => t.id == taskId);
    });
  }

  @override
  Future sync(List<Task> tasks, Function setState) async {
    await getIt<BackendTask>().deleteTask(taskId);
  }
}
