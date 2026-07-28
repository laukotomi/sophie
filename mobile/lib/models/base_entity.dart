import 'package:flutter/material.dart';

class BaseEntity {
  final String id;
  final DateTime createdAt;
  DateTime updatedAt;

  BaseEntity({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  @mustCallSuper
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Extract base entity fields from JSON
  static ({String id, DateTime createdAt, DateTime updatedAt}) parseBaseFields(
    Map<String, dynamic> json,
  ) {
    return (
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
    );
  }
}
