class TaskAlert {
  final int id;
  final DateTime? alertAt;
  final String? timeBefore;

  const TaskAlert({required this.id, this.alertAt, this.timeBefore});

  factory TaskAlert.fromJson(Map<String, dynamic> json) => TaskAlert(
    id: json['id'] as int,
    alertAt: json['alertAt'] != null
        ? DateTime.parse(json['alertAt'] as String)
        : null,
    timeBefore: json['timeBefore'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'alertAt': alertAt?.toIso8601String(),
    'timeBefore': timeBefore,
  };
}
