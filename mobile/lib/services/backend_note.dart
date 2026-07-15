import 'package:http/http.dart' as http;
import 'package:sophie/events/note_saved_event.dart';
import 'dart:convert';

import 'package:sophie/models/note_history_entry.dart';
import 'package:sophie/models/note_lock_result.dart';
import 'package:sophie/services/backend.dart';

class NoteLockedException implements Exception {
  const NoteLockedException();
}

class BackendNote {
  final Duration timeout;
  final String baseUrl;
  final Map<String, String> Function(bool json) getHeaders;
  final Future Function(int statusCode) checkUnauthorized;

  BackendNote({
    required this.baseUrl,
    required this.getHeaders,
    required this.checkUnauthorized,
    required this.timeout,
  });

  Future<http.MultipartRequest> _buildNoteRequest({
    required String method,
    required String noteId,
    required String text,
    required List<({String userId, String right})> collaborators,
    int? fixedPosition,
    String? color,
    required bool dontFold,
    required bool todoList,
    required List<({String id, String path, String name})> files,
  }) async {
    final request =
        http.MultipartRequest(method, Uri.parse('$baseUrl/api/notes'))
          ..headers.addAll(getHeaders(false))
          ..fields['text'] = text;
    request.fields['noteId'] = noteId;
    if (collaborators.isNotEmpty) {
      request.fields['collaborators'] = jsonEncode(
        collaborators
            .map((c) => {'userId': c.userId, 'right': c.right})
            .toList(),
      );
    }
    if (fixedPosition != null) {
      request.fields['fixedPosition'] = fixedPosition.toString();
    }
    if (color != null) {
      request.fields['color'] = color;
    }
    request.fields['dontFold'] = dontFold.toString();
    request.fields['todoList'] = todoList.toString();
    for (final file in files) {
      request.fields['fileIds'] = file.id;
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          file.path,
          filename: file.name,
        ),
      );
    }
    return request;
  }

  /// Creates a new note when [noteId] is null, or updates an existing one.
  Future saveNote(NoteSavedEvent event) async {
    final request = await _buildNoteRequest(
      method: event.isNew ? 'POST' : 'PUT',
      noteId: event.noteId,
      text: event.text,
      collaborators: event.collaborators,
      fixedPosition: event.fixedPosition,
      color: event.color,
      dontFold: event.dontFold,
      todoList: event.todoList,
      files: event.newFiles,
    );

    final response = await http.Response.fromStream(
      await request.send().timeout(timeout),
    );

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw UnauthorizedException();
    if (response.statusCode == 404) throw NotFoundException();
    if (response.statusCode != (event.isNew ? 201 : 204)) {
      throw Exception('Failed to save note: ${response.statusCode}');
    }
  }

  /// Acquires the edit lock for [noteId].
  /// Returns the latest note text on success.
  /// Throws [NoteLockedException] if another user holds the lock.
  Future<NoteLockResult> acquireNoteLock(String noteId) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 423) throw NoteLockedException();
    if (response.statusCode == 403) throw UnauthorizedException();
    if (response.statusCode == 404) throw NotFoundException();
    if (response.statusCode != 200) {
      throw Exception('Failed to acquire note lock: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return NoteLockResult.fromJson(json);
  }

  Future releaseNoteLock(String noteId) async {
    await http
        .delete(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);
    // Fire-and-forget: ignore errors — lock will expire on its own.
  }

  Future refreshNoteLock(String noteId) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 409) throw Exception('Lock not held');
    if (response.statusCode != 204) {
      throw Exception('Failed to refresh note lock: ${response.statusCode}');
    }
  }

  Future deleteNote(String noteId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/notes'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw UnauthorizedException();
    if (response.statusCode == 404) throw NotFoundException();
    if (response.statusCode != 204) {
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }

  Future<List<NoteHistoryEntry>> getNoteHistory(String noteId) async {
    final response = await http
        .get(
          Uri.parse(
            '$baseUrl/api/notes/history?noteId=${Uri.encodeQueryComponent(noteId)}',
          ),
          headers: getHeaders(false),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw UnauthorizedException();
    if (response.statusCode == 404) throw NotFoundException();
    if (response.statusCode != 200) {
      throw Exception('Failed to load note history: ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => NoteHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
