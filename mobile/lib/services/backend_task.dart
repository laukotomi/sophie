import 'package:http/http.dart' as http;
import 'package:sophie/events/task_saved_event.dart';
import 'dart:convert';

import 'package:sophie/utils/time_utils.dart';

class BackendTask {
  final Duration timeout;
  final String baseUrl;
  final Map<String, String> Function(bool json) getHeaders;
  final Future Function(int statusCode) checkUnauthorized;

  BackendTask({
    required this.baseUrl,
    required this.getHeaders,
    required this.checkUnauthorized,
    required this.timeout,
  });

  Future setTaskDone(String taskId, DateTime? doneAt) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({
            'taskId': taskId,
            'doneAt': doneAt?.toUtc().toIso8601String(),
          }),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }

  Future deleteTask(String taskId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({'taskId': taskId}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  Future deleteTaskGroup(String taskId, String groupId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/tasks/group'),
          headers: getHeaders(true),
          body: jsonEncode({'taskId': taskId, 'groupId': groupId}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete task group: ${response.statusCode}');
    }
  }

  /// Creates a new task when [taskId] is null, or updates an existing one.
  Future saveTask(TaskSavedEvent event) async {
    final body = jsonEncode({
      'taskId': event.taskId,
      'text': event.text,
      if (event.rrule != null && event.rrule!.isNotEmpty) 'rrule': event.rrule,
      if (event.dueAt != null) 'dueAt': event.dueAt!.toIso8601String(),
      'color': event.color,
      if (event.collaboratorIds.isNotEmpty)
        'collaboratorIds': event.collaboratorIds,
      if (event.alerts.isNotEmpty)
        'alerts': event.alerts
            .map(
              (a) => a.alertAt != null
                  ? {
                      'type': 'absolute',
                      'alertAt': a.alertAt!.toUtc().toIso8601String(),
                    }
                  : {
                      'type': 'relative',
                      'timeBefore': TimeUtils.durationToTime(a.timeBefore!),
                    },
            )
            .toList(),
      if (event.recurringGroupId != null)
        'recurringGroupId': event.recurringGroupId,
      'timestamp': event.createdAt.toUtc().toIso8601String(),
    });

    final uri = Uri.parse('$baseUrl/api/tasks');
    final headers = getHeaders(true);
    final response =
        await (event.isNew
                ? http.post(uri, headers: headers, body: body)
                : http.put(uri, headers: headers, body: body))
            .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    final expectedStatus = event.isNew ? 201 : 204;
    if (response.statusCode != expectedStatus) {
      throw Exception('Failed to save task: ${response.statusCode}');
    }
  }
}
