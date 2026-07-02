import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:sophie/models/note_history_entry.dart';

class NoteLockedException implements Exception {
  const NoteLockedException();
}

/// Thrown when the note no longer exists or the user lost access to it.
/// The pending offline edit should be discarded.
class NoteGoneException implements Exception {
  const NoteGoneException();
}

class BackendNote {
  final Duration timeout;
  final String baseUrl;
  final Map<String, String> Function(bool json) getHeaders;
  final Function(int statusCode) checkUnauthorized;

  BackendNote({
    required this.baseUrl,
    required this.getHeaders,
    required this.checkUnauthorized,
    required this.timeout,
  });

  Future<http.MultipartRequest> _buildNoteRequest(
    String method, {
    String? noteId,
    required String text,
    required List<({String userId, String right})> collaborators,
    int? fixedPosition,
    String? color,
    bool dontFold = false,
    bool todoList = false,
    required List<({String path, String name})> files,
  }) async {
    final request =
        http.MultipartRequest(method, Uri.parse('$baseUrl/api/notes'))
          ..headers.addAll(getHeaders(false))
          ..fields['text'] = text;
    if (noteId != null) request.fields['noteId'] = noteId;
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
  Future<void> saveNote(
    String? noteId,
    String text, {
    List<({String userId, String right})> collaborators = const [],
    int? fixedPosition,
    String? color,
    bool dontFold = false,
    bool todoList = false,
    List<({String path, String name})> files = const [],
  }) async {
    final request = await _buildNoteRequest(
      noteId != null ? 'PUT' : 'POST',
      noteId: noteId,
      text: text,
      collaborators: collaborators,
      fixedPosition: fixedPosition,
      color: color,
      dontFold: dontFold,
      todoList: todoList,
      files: files,
    );

    final response = await http.Response.fromStream(
      await request.send().timeout(timeout),
    );

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
    if (response.statusCode != 204) {
      throw Exception('Failed to save note: ${response.statusCode}');
    }
  }

  /// Acquires the edit lock for [noteId].
  /// Returns the latest note text on success.
  /// Throws [NoteLockedException] if another user holds the lock.
  Future<String> acquireNoteLock(String noteId) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 423) throw NoteLockedException();
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
    if (response.statusCode != 200) {
      throw Exception('Failed to acquire note lock: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['text'] as String;
  }

  Future<void> releaseNoteLock(String noteId) async {
    await http
        .delete(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);
    // Fire-and-forget: ignore errors — lock will expire on its own.
  }

  /// Syncs a single offline edit to the server using LWW conflict resolution.
  ///
  /// Returns `true` if a conflict occurred (server or local won — either way
  /// the edit was applied by one side; history preserves the loser).
  ///
  /// Throws [NoteGoneException] when the note was deleted or access was revoked
  /// — the caller should discard the pending edit from the queue.
  ///
  /// Throws [Exception] on network errors or when the note is currently locked —
  /// the caller should leave the edit in the queue and retry later.
  Future<bool> syncOfflineEdit({
    required String noteId,
    required String text,
    List<({String userId, String right})> collaborators = const [],
    String? color,
    bool dontFold = false,
    bool todoList = false,
    required String baseUpdatedAt,
    required String localSavedAt,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/notes/sync'),
          headers: getHeaders(true),
          body: jsonEncode({
            'noteId': noteId,
            'text': text,
            if (collaborators.isNotEmpty)
              'collaborators': collaborators
                  .map((c) => {'userId': c.userId, 'right': c.right})
                  .toList(),
            'color': color,
            'dontFold': dontFold,
            'todoList': todoList,
            'baseUpdatedAt': baseUpdatedAt,
            'localSavedAt': localSavedAt,
          }),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 404 || response.statusCode == 403) {
      throw const NoteGoneException();
    }
    if (response.statusCode != 200) {
      throw Exception('Sync failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['conflicted'] as bool? ?? false;
  }

  Future<void> refreshNoteLock(String noteId) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/api/notes/edit'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 409) throw Exception('Lock not held');
    if (response.statusCode != 204) {
      throw Exception('Failed to refresh note lock: ${response.statusCode}');
    }
  }

  Future<void> deleteNote(String noteId) async {
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/notes'),
          headers: getHeaders(true),
          body: jsonEncode({'noteId': noteId}),
        )
        .timeout(timeout);

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
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

    checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('Note not found');
    if (response.statusCode != 200) {
      throw Exception('Failed to load note history: ${response.statusCode}');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => NoteHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
