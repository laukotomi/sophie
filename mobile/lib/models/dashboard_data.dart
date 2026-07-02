import 'package:sophie/models/app_user.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/models/task.dart';

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
