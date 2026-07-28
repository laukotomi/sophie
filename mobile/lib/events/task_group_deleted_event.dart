import 'package:flutter/foundation.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_task.dart';
import 'package:sophie/services/task_events.dart';

class TaskGroupDeletedEvent extends TaskEvent {
  final String taskId;

  TaskGroupDeletedEvent({required this.taskId});

  @override
  String get type => 'task_group_deleted';

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'taskId': taskId};
  }

  factory TaskGroupDeletedEvent.fromJson(Map<String, dynamic> m) {
    return TaskGroupDeletedEvent(taskId: m['taskId'] as String);
  }

  @override
  Future onApply(List<Task> tasks, Function setState) async {
    final task = tasks.firstWhere((t) => t.id == taskId);

    if (!kIsWeb) {
      final toRemove = tasks
          .where((t) => t.recurringGroupId == task.recurringGroupId)
          .toList();
      for (final t in toRemove) {
        await AlertNotifications.cancelForTask(t.id);
      }
    }

    setState(() {
      tasks.removeWhere((t) => t.recurringGroupId == task.recurringGroupId);
    });
  }

  @override
  Future onSync(List<Task> tasks, Function setState) async {
    await getIt<BackendTask>().deleteTaskGroup(taskId);
  }
}
