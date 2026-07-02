import 'package:http/http.dart' as http;
import 'dart:convert';

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

  Future<String> createTask({
    required String text,
    String? rrule,
    DateTime? dueAt,
    String? color,
    List<String> collaboratorIds = const [],
    List<({DateTime? alertAt, Duration? timeBefore})> alerts = const [],
  }) async {
    String pad(int n) => n.toString().padLeft(2, '0');
    String durationToTime(Duration d) =>
        '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({
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
                            'timeBefore': durationToTime(a.timeBefore!),
                          },
                  )
                  .toList(),
          }),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode != 201) {
      throw Exception('Failed to create task: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['id'] as String;
  }

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

  Future<void> updateTask({
    required String taskId,
    required String text,
    String? rrule,
    DateTime? dueAt,
    String? color,
    List<String> collaboratorIds = const [],
    List<({DateTime? alertAt, Duration? timeBefore})> alerts = const [],
  }) async {
    String pad(int n) => n.toString().padLeft(2, '0');
    String durationToTime(Duration d) =>
        '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/tasks'),
          headers: getHeaders(true),
          body: jsonEncode({
            'taskId': taskId,
            'text': text,
            if (rrule != null && rrule.isNotEmpty) 'rrule': rrule,
            if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
            'color': color,
            if (collaboratorIds.isNotEmpty) 'collaboratorIds': collaboratorIds,
            'alerts': alerts
                .map(
                  (a) => a.alertAt != null
                      ? {
                          'type': 'absolute',
                          'alertAt': a.alertAt!.toUtc().toIso8601String(),
                        }
                      : {
                          'type': 'relative',
                          'timeBefore': durationToTime(a.timeBefore!),
                        },
                )
                .toList(),
          }),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode != 204) {
      throw Exception('Failed to update task: ${response.statusCode}');
    }
  }
}
