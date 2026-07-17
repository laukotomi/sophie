import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_task.dart';
import 'package:sophie/services/task_events.dart';
import 'package:sophie/utils/task_utils.dart';

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

  @override
  Future apply(List<Task> tasks, Function setState) async {
    final task = tasks.firstWhere(
      (t) => t.id == this.task.id,
    ); // required because this task can be initialized from notification event
    setState(() {
      task.doneAt = done ? DateTime.now() : null;
      TaskUtils.sortTasks(tasks);
    });

    if (done) {
      await AlertNotifications.cancelForTask(task.id);
    } else {
      await AlertNotifications.scheduleAlerts(
        task.id,
        task.dueAt,
        task.alerts,
        task.text,
      );
    }
  }

  @override
  Future sync(List<Task> tasks, Function setState) async {
    final next = await getIt<BackendTask>().setTaskDone(task.id, done);

    if (next != null) {
      await TaskSavedEvent(
        alerts: task.alerts.where((a) => a.alertAt == null).toList(),
        collaboratorIds: task.collaborators,
        color: task.color,
        dueAt: next.nextDueAt,
        isNew: true,
        rrule: task.rrule,
        taskId: next.nextTaskId,
        text: task.text,
        recurringGroupId: task.recurringGroupId,
      ).apply(tasks, setState);
    }
  }
}
