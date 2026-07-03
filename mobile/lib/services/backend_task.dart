import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:sophie/utils/time_utils.dart';

class BackendTask {
  final Duration timeout;
  final String baseUrl;
  final Map<String, String> Function(bool json) getHeaders;
  final Function(int statusCode) checkUnauthorized;

  BackendTask({
    required this.baseUrl,
    required this.getHeaders,
    required this.checkUnauthorized,
    required this.timeout,
  });

  Future<({String nextTaskId, DateTime nextDueAt})?> setTaskDone({
    required String taskId,
    required bool done,
  }) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({'taskId': taskId, 'done': done}),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
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

  Future<void> deleteTask({required String taskId}) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({'taskId': taskId}),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.statusCode}');
    }
  }

  /// Creates a new task when [taskId] is null, or updates an existing one.
  /// Returns the task ID (server-assigned for creates, same value for updates).
  Future<String> saveTask(
    String? taskId,
    String text, {
    String? rrule,
    DateTime? dueAt,
    String? color,
    List<String> collaboratorIds = const [],
    List<({DateTime? alertAt, Duration? timeBefore})> alerts = const [],
  }) async {
    final body = jsonEncode({
      'taskId': ?taskId,
      'text': text,
      if (rrule != null && rrule.isNotEmpty) 'rrule': rrule,
      if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      'color': color,
      if (collaboratorIds.isNotEmpty) 'collaboratorIds': collaboratorIds,
      if (alerts.isNotEmpty)
        'alerts': alerts
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
        await (taskId != null
                ? http.put(uri, headers: headers, body: body)
                : http.post(uri, headers: headers, body: body))
            .timeout(timeout);

    checkUnauthorized(response.statusCode);
    final expectedStatus = taskId != null ? 204 : 201;
    if (response.statusCode != expectedStatus) {
      throw Exception('Failed to save task: ${response.statusCode}');
    }
    if (taskId != null) return taskId;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }
}
