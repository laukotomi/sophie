class ScheduledNotification {
  final int id;
  final String body;
  final DateTime scheduledDateTime;
  final String taskId;
  bool muted;
  bool rescheduled = false;

  ScheduledNotification({
    required this.id,
    required this.body,
    required this.scheduledDateTime,
    required this.muted,
    required this.taskId,
    this.rescheduled = false,
  });

  factory ScheduledNotification.fromJson(Map<String, dynamic> m) =>
      ScheduledNotification(
        id: m['id'] as int,
        body: m['body'] as String,
        scheduledDateTime: DateTime.parse(m['scheduledDateTime'] as String),
        muted: m['muted'] as bool,
        taskId: m['taskId'] as String,
        rescheduled: m['rescheduled'] as bool,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'body': body,
    'scheduledDateTime': scheduledDateTime.toIso8601String(),
    'muted': muted,
    'taskId': taskId,
    'rescheduled': rescheduled,
  };
}
