void saveBytesToBrowserDownload({
  required List<int> bytes,
  required String filename,
  String? mimeType,
}) {
  throw UnsupportedError('Browser download is only available on web.');
}