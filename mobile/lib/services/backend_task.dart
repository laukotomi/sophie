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

  Future<({String nextTaskId, DateTime nextDueAt})?> setTaskDone(
    String taskId,
    bool done,
  ) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({'taskId': taskId, 'done': done}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        nextTaskId: json['nextTaskId'] as String,
        nextDueAt: DateTime.parse(json['nextDueAt'] as String),
      );
    }
    if (response.statusCode != 204) {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
    return null;
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
