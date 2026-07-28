import 'package:sophie/models/alert.dart';
import 'package:sophie/models/base_entity.dart';

class Task extends BaseEntity {
  String text;
  String? rrule;
  String? color;
  DateTime? dueAt;
  DateTime? doneAt;
  final bool isOwner;
  List<String> collaborators;
  List<Alert> alerts;
  String? recurringGroupId;

  Task({
    required super.id,
    required this.text,
    required this.rrule,
    required this.color,
    required this.dueAt,
    required this.doneAt,
    required super.createdAt,
    required super.updatedAt,
    required this.isOwner,
    required this.collaborators,
    required this.alerts,
    required this.recurringGroupId,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    final baseFields = BaseEntity.parseBaseFields(json);

    return Task(
      id: baseFields.id,
      text: json['text'] as String,
      rrule: json['rrule'] as String?,
      color: json['color'] as String?,
      dueAt: json['dueAt'] != null
          ? DateTime.parse(json['dueAt'] as String)
          : null,
      doneAt: json['doneAt'] != null
          ? DateTime.parse(json['doneAt'] as String).toLocal()
          : null,
      createdAt: baseFields.createdAt,
      updatedAt: baseFields.updatedAt,
      isOwner: json['isOwner'] as bool,
      collaborators: (json['collaborators'] as List<dynamic>)
          .map((c) => c as String)
          .toList(),
      alerts: (json['alerts'] as List<dynamic>)
          .map((a) => Alert.fromJson(a as Map<String, dynamic>))
          .toList(),
      recurringGroupId: json['recurringGroupId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'text': text,
    'rrule': rrule,
    'color': color,
    'dueAt': dueAt?.toIso8601String(),
    'doneAt': doneAt?.toIso8601String(),
    'isOwner': isOwner,
    'collaborators': collaborators,
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'recurringGroupId': recurringGroupId,
  };
}
