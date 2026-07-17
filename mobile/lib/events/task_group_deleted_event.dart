import 'package:sophie/main.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_task.dart';
import 'package:sophie/services/task_events.dart';

class TaskGroupDeletedEvent extends TaskEvent {
  final String taskId;
  final String groupId;

  TaskGroupDeletedEvent({required this.taskId, required this.groupId});

  @override
  String get type => 'task_group_deleted';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'taskId': taskId, 'groupId': groupId};
  }

  factory TaskGroupDeletedEvent.fromJson(Map<String, dynamic> m) {
    return TaskGroupDeletedEvent(
      taskId: m['taskId'] as String,
      groupId: m['groupId'] as String,
    );
  }

  @override
  Future apply(List<Task> tasks, Function setState) async {
    final toRemove = tasks.where((t) => t.recurringGroupId == groupId).toList();
    for (final t in toRemove) {
      await AlertNotifications.cancelForTask(t.id);
    }
    setState(() {
      tasks.removeWhere((t) => t.recurringGroupId == groupId);
    });
  }

  @override
  Future sync(List<Task> tasks, Function setState) async {
    await getIt<BackendTask>().deleteTaskGroup(taskId, groupId);
  }
}
