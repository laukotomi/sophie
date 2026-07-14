class ScheduledNotification {
  final int id;
  final String body;
  final DateTime scheduledDateTime;
  final bool muted;
  final String taskId;

  ScheduledNotification({
    required this.id,
    required this.body,
    required this.scheduledDateTime,
    required this.muted,
    required this.taskId,
  });

  factory ScheduledNotification.fromJson(Map<String, dynamic> m) =>
      ScheduledNotification(
        id: m['id'] as int,
        body: m['body'] as String,
        scheduledDateTime: DateTime.parse(m['scheduledDateTime'] as String),
        muted: m['muted'] as bool,
        taskId: m['taskId'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'scheduledDateTime': scheduledDateTime.toIso8601String(),
    'muted': muted,
    'taskId': taskId,
  };
}
