class NoteHistoryEntry {
  final int id;
  final String text;
  final DateTime createdAt;

  const NoteHistoryEntry({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory NoteHistoryEntry.fromJson(Map<String, dynamic> json) =>
      NoteHistoryEntry(
        id: json['id'] as int,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}
