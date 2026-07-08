import 'package:sophie/models/alert.dart';
import 'package:sophie/services/task_events.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class TaskSavedEvent extends TaskEvent {
  late final bool isNew;
  late final String taskId;
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
  }) {
    isNew = taskId == null;
    this.taskId = taskId ?? _uuid.v4();
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
    );
  }
}
