class NoteFile {
  final String? id;
  final String fileName;

  const NoteFile({this.id, required this.fileName});

  factory NoteFile.fromJson(Map<String, dynamic> json) =>
      NoteFile(id: json['id'] as String?, fileName: json['fileName'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'fileName': fileName};
}
