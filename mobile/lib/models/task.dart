import 'package:sophie/models/alert.dart';

class Task {
  final String id;
  final String text;
  final String? rrule;
  final String? color;
  final DateTime? dueAt;
  final DateTime? doneAt;
  final DateTime createdAt;
  final bool isOwner;
  final List<String> collaborators;
  final List<Alert> alerts;

  const Task({
    required this.id,
    required this.text,
    this.rrule,
    this.color,
    this.dueAt,
    this.doneAt,
    required this.createdAt,
    required this.isOwner,
    required this.collaborators,
    required this.alerts,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    text: json['text'] as String,
    rrule: json['rrule'] as String?,
    color: json['color'] as String?,
    dueAt: json['dueAt'] != null
        ? DateTime.parse(json['dueAt'] as String)
        : null,
    doneAt: json['doneAt'] != null
        ? DateTime.parse(json['doneAt'] as String).toLocal()
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    isOwner: json['isOwner'] as bool,
    collaborators: (json['collaborators'] as List<dynamic>)
        .map((c) => c as String)
        .toList(),
    alerts: (json['alerts'] as List<dynamic>)
        .map((a) => Alert.fromJson(a as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'rrule': rrule,
    'color': color,
    'dueAt': dueAt?.toIso8601String(),
    'doneAt': doneAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'isOwner': isOwner,
    'collaborators': collaborators,
    'alerts': alerts.map((a) => a.toJson()).toList(),
  };
}
