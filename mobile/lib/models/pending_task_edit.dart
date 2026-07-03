class PendingTaskEdit {
  final String taskId; // 'local_<timestamp>' for new tasks, real ID for edits
  final bool isNew;
  final String text;
  final String? rrule;
  final String? dueAt; // ISO-8601 UTC, null if not set
  final String? color;
  final List<String> collaboratorIds;
  // Each entry: {'type':'absolute','alertAt':'...'} or {'type':'relative','timeBefore':'HH:MM:SS'}
  final List<Map<String, dynamic>> alerts;

  const PendingTaskEdit({
    required this.taskId,
    this.isNew = false,
    required this.text,
    this.rrule,
    this.dueAt,
    this.color,
    this.collaboratorIds = const [],
    this.alerts = const [],
  });

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'isNew': isNew,
    'text': text,
    'rrule': rrule,
    'dueAt': dueAt,
    'color': color,
    'collaboratorIds': collaboratorIds,
    'alerts': alerts,
  };

  factory PendingTaskEdit.fromJson(Map<String, dynamic> m) => PendingTaskEdit(
    taskId: m['taskId'] as String,
    isNew: m['isNew'] as bool? ?? false,
    text: m['text'] as String,
    rrule: m['rrule'] as String?,
    dueAt: m['dueAt'] as String?,
    color: m['color'] as String?,
    collaboratorIds: (m['collaboratorIds'] as List<dynamic>? ?? [])
        .cast<String>()
        .toList(),
    alerts: (m['alerts'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList(),
  );
}
