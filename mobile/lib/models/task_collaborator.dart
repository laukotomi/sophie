class TaskCollaborator {
  final String id;
  final String name;
  final String email;

  const TaskCollaborator({
    required this.id,
    required this.name,
    required this.email,
  });

  factory TaskCollaborator.fromJson(Map<String, dynamic> json) =>
      TaskCollaborator(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}
