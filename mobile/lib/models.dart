class AppUser {
  final String id;
  final String name;
  final String email;

  const AppUser({required this.id, required this.name, required this.email});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class NoteFile {
  final String id;
  final String fileName;

  const NoteFile({required this.id, required this.fileName});

  factory NoteFile.fromJson(Map<String, dynamic> json) =>
      NoteFile(id: json['id'] as String, fileName: json['fileName'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'fileName': fileName};
}

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

class Note {
  final String id;
  String text;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String right;
  final bool isOwner;
  final String ownerId;
  final int? position;
  final List<NoteCollaborator> collaborators;
  final List<NoteFile> files;

  Note({
    required this.id,
    required this.text,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.right,
    required this.isOwner,
    required this.ownerId,
    this.position,
    required this.collaborators,
    required this.files,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    text: json['text'] as String,
    color: json['color'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
    right: json['right'] as String,
    isOwner: json['isOwner'] as bool,
    ownerId: json['ownerId'] as String,
    position: json['position'] as int?,
    collaborators: (json['collaborators'] as List<dynamic>)
        .map((c) => NoteCollaborator.fromJson(c as Map<String, dynamic>))
        .toList(),
    files: (json['files'] as List<dynamic>? ?? [])
        .map((f) => NoteFile.fromJson(f as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'right': right,
    'isOwner': isOwner,
    'ownerId': ownerId,
    'position': position,
    'collaborators': collaborators.map((c) => c.toJson()).toList(),
    'files': files.map((f) => f.toJson()).toList(),
  };
}

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

class Task {
  final String id;
  final String text;
  final String? rrule;
  final String? color;
  final DateTime? dueAt;
  final DateTime? doneAt;
  final DateTime createdAt;
  final bool isOwner;
  final List<TaskCollaborator> collaborators;
  final List<TaskAlert> alerts;

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
        .map((c) => TaskCollaborator.fromJson(c as Map<String, dynamic>))
        .toList(),
    alerts: (json['alerts'] as List<dynamic>)
        .map((a) => TaskAlert.fromJson(a as Map<String, dynamic>))
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
    'collaborators': collaborators.map((c) => c.toJson()).toList(),
    'alerts': alerts.map((a) => a.toJson()).toList(),
  };
}

class DashboardData {
  final AppUser user;
  final List<AppUser> users;
  final List<Note> notes;
  final List<Task> tasks;

  const DashboardData({
    required this.user,
    required this.users,
    required this.notes,
    required this.tasks,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    users: (json['users'] as List<dynamic>)
        .map((u) => AppUser.fromJson(u as Map<String, dynamic>))
        .toList(),
    notes: (json['notes'] as List<dynamic>)
        .map((n) => Note.fromJson(n as Map<String, dynamic>))
        .toList(),
    tasks: (json['tasks'] as List<dynamic>? ?? [])
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'users': users.map((u) => u.toJson()).toList(),
    'notes': notes.map((n) => n.toJson()).toList(),
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };
}
