import 'package:sophie/models/task.dart';

class TaskUtils {
  static void sortTasks(List<Task> tasks) {
    tasks.sort((a, b) {
      if (a.doneAt != null && b.doneAt == null) return 1;
      if (a.doneAt == null && b.doneAt != null) return -1;
      if (a.doneAt != null && b.doneAt != null) {
        return a.doneAt!.compareTo(b.doneAt!);
      }

      if (a.dueAt == null && b.dueAt != null) return -1;
      if (a.dueAt != null && b.dueAt == null) return 1;
      if (a.dueAt != null && b.dueAt != null) {
        final dueDiff = a.dueAt!.compareTo(b.dueAt!);
        if (dueDiff != 0) return dueDiff;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
  }
}
