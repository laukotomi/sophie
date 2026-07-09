class PendingSnooze {
  final int alarmId;
  final String taskId;
  final String body;

  const PendingSnooze({
    required this.alarmId,
    required this.taskId,
    required this.body,
  });

  factory PendingSnooze.fromJson(Map<String, dynamic> m) => PendingSnooze(
    alarmId: m['alarmId'] as int,
    taskId: m['taskId'] as String,
    body: m['body'] as String,
  );

  Map<String, dynamic> toJson() => {
    'alarmId': alarmId,
    'taskId': taskId,
    'body': body,
  };
}
