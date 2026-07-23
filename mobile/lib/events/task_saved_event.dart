import 'package:sophie/main.dart';
import 'package:sophie/models/alert.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_task.dart';
import 'package:sophie/services/task_events.dart';
import 'package:sophie/utils/task_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';

const _uuid = Uuid();

class TaskSavedEvent extends TaskEvent {
  late final bool isNew;
  late final String taskId;
  late final String? recurringGroupId;
  final String text;
  final String? rrule;
  final DateTime? dueAt;
  final String? color;
  final List<String> collaboratorIds;
  final List<Alert> alerts;

  TaskSavedEvent({
    required String? taskId,
    required this.text,
    required this.rrule,
    required this.dueAt,
    required this.color,
    required this.collaboratorIds,
    required this.alerts,
    String? recurringGroupId,
    bool? isNew,
  }) {
    this.isNew = isNew ?? taskId == null;
    this.taskId = taskId ?? _uuid.v4();
    this.recurringGroupId = rrule != null
        ? recurringGroupId ?? this.taskId
        : null;
  }

  @override
  String get type => 'task_saved';

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'taskId': taskId,
      'text': text,
      'rrule': rrule,
      'dueAt': dueAt?.toIso8601String(),
      'color': color,
      'collaboratorIds': collaboratorIds,
      'alerts': alerts.map((a) => a.toJson()).toList(),
      'isNew': isNew,
      'recurringGroupId': recurringGroupId,
    };
  }

  factory TaskSavedEvent.fromJson(Map<String, dynamic> m) {
    return TaskSavedEvent(
      taskId: m['taskId'] as String?,
      text: m['text'] as String,
      rrule: m['rrule'] as String?,
      dueAt: m['dueAt'] != null ? DateTime.parse(m['dueAt'] as String) : null,
      color: m['color'] as String?,
      collaboratorIds: (m['collaboratorIds'] as List<dynamic>)
          .map((id) => id as String)
          .toList(),
      alerts: (m['alerts'] as List<dynamic>)
          .map((a) => Alert.fromJson(a as Map<String, dynamic>))
          .toList(),
      isNew: m['isNew'] as bool,
      recurringGroupId: m['recurringGroupId'] as String?,
    );
  }

  @override
  Future apply(List<Task> tasks, Function setState) async {
    if (!isNew) {
      final task = tasks.firstWhereOrNull((t) => t.id == taskId);
      if (task == null) {
        return;
      }

      setState(() {
        task
          ..alerts = alerts
          ..collaborators = collaboratorIds
          ..color = color
          ..dueAt = dueAt
          ..rrule = rrule
          ..text = text
          ..recurringGroupId = recurringGroupId;
      });
    } else {
      setState(() {
        tasks.add(
          Task(
            id: taskId,
            text: text,
            rrule: rrule,
            color: color,
            dueAt: dueAt,
            doneAt: null,
            createdAt: DateTime.now(),
            isOwner: true,
            collaborators: collaboratorIds,
            alerts: alerts,
            recurringGroupId: recurringGroupId,
          ),
        );
      });
    }

    await AlertNotifications.scheduleAlerts(taskId, dueAt, alerts, text);

    setState(() {
      TaskUtils.sortTasks(tasks);
    });
  }

  @override
  Future sync(List<Task> tasks, Function setState) async {
    await getIt<BackendTask>().saveTask(this);
  }
}
