import 'package:rrule/rrule.dart';
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
  TaskSavedEvent? nextTaskEvent;

  TaskSetDoneEvent({
    required this.task,
    required this.done,
    this.nextTaskEvent,
  });

  @override
  String get type => 'task_set_done';

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'task': task.toJson(),
      'done': done,
      'nextTaskEvent': nextTaskEvent?.toJson(),
    };
  }

  factory TaskSetDoneEvent.fromJson(Map<String, dynamic> m) {
    return TaskSetDoneEvent(
      task: Task.fromJson(m['task'] as Map<String, dynamic>),
      done: m['done'] as bool,
      nextTaskEvent: m['nextTaskEvent'] != null
          ? TaskSavedEvent.fromJson(m['nextTaskEvent'] as Map<String, dynamic>)
          : null,
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

    if (done && task.rrule != null && task.dueAt != null) {
      final rrule = RecurrenceRule.fromString(task.rrule!);

      final startFakeUtc = DateTime.utc(
        task.dueAt!.year,
        task.dueAt!.month,
        task.dueAt!.day,
        task.dueAt!.hour,
        task.dueAt!.minute,
      );

      final nextDueAtUtc = rrule
          .getInstances(start: startFakeUtc, after: startFakeUtc)
          .firstOrNull;

      if (nextDueAtUtc != null) {
        final nextDueAt = DateTime(
          nextDueAtUtc.year,
          nextDueAtUtc.month,
          nextDueAtUtc.day,
          nextDueAtUtc.hour,
          nextDueAtUtc.minute,
        );

        final existsAlready = tasks.any(
          (t) =>
              t.dueAt == nextDueAt &&
              t.recurringGroupId == task.recurringGroupId,
        );

        if (!existsAlready) {
          nextTaskEvent = TaskSavedEvent(
            alerts: task.alerts.where((a) => a.timeBefore != null).toList(),
            collaboratorIds: task.collaborators,
            color: task.color,
            dueAt: nextDueAt,
            rrule: task.rrule,
            text: task.text,
            recurringGroupId: task.recurringGroupId,
            taskId: null,
          );
          await nextTaskEvent!.apply(tasks, setState);
          nextTaskEvent!.applied = true;
        }
      }
    }
  }

  @override
  Future sync(List<Task> tasks, Function setState) async {
    await getIt<BackendTask>().setTaskDone(task.id, task.doneAt);
    if (nextTaskEvent != null) {
      await nextTaskEvent!.sync(tasks, setState);
      nextTaskEvent!.synced = true;
    }
  }
}
