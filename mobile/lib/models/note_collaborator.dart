class NoteCollaborator {
  final String id;
  final String name;
  final String email;
  final String right;

  const NoteCollaborator({
    required this.id,
    required this.name,
    required this.email,
    required this.right,
  });

  factory NoteCollaborator.fromJson(Map<String, dynamic> json) =>
      NoteCollaborator(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        right: json['right'] as String,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'right': right,
  };
}
