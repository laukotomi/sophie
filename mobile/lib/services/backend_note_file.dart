import 'dart:io';
import 'package:http/http.dart' as http;

class BackendNoteFile {
  static const _uploadTimeout = Duration(seconds: 60);

  final Duration timeout;
  final String baseUrl;
  final Map<String, String> Function(bool json) getHeaders;
  final Future Function(int statusCode) checkUnauthorized;

  BackendNoteFile({
    required this.baseUrl,
    required this.getHeaders,
    required this.checkUnauthorized,
    required this.timeout,
  });

  Future downloadFileTo(String fileId, String destPath) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}'),
    )..headers.addAll(getHeaders(false));

    final streamed = await request.send().timeout(_uploadTimeout);

    await checkUnauthorized(streamed.statusCode);
    if (streamed.statusCode == 403) throw Exception('Forbidden');
    if (streamed.statusCode == 404) throw Exception('File not found');
    if (streamed.statusCode != 200) {
      throw Exception('Failed to download file: ${streamed.statusCode}');
    }

    final sink = File(destPath).openWrite();
    try {
      await streamed.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  Future deleteFile(String fileId) async {
    final response = await http
        .delete(
          Uri.parse(
            '$baseUrl/api/files?id=${Uri.encodeQueryComponent(fileId)}',
          ),
          headers: getHeaders(false),
        )
        .timeout(timeout);

    await checkUnauthorized(response.statusCode);
    if (response.statusCode == 403) throw Exception('Forbidden');
    if (response.statusCode == 404) throw Exception('File not found');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete file: ${response.statusCode}');
    }
  }
}
