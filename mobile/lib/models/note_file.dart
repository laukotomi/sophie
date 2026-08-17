class NoteFile {
  final String id;
  final String fileName;
  final String?
  path; // Optional path for local files, null for files that are only on the server.

  const NoteFile({required this.id, required this.fileName, this.path});

  factory NoteFile.fromJson(Map<String, dynamic> json) => NoteFile(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    path: json['path'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'path': path,
  };
}
