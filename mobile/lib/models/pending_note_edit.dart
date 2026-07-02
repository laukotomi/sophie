class PendingNoteEdit {
  final String noteId;
  final bool isNew;
  final String text;
  final String? color;
  final bool dontFold;
  final bool todoList;
  final List<({String userId, String right})> collaborators;
  final String? baseUpdatedAt; // null for new notes
  final String localSavedAt;

  const PendingNoteEdit({
    required this.noteId,
    this.isNew = false,
    required this.text,
    this.color,
    required this.dontFold,
    required this.todoList,
    this.collaborators = const [],
    this.baseUpdatedAt,
    required this.localSavedAt,
  });

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'isNew': isNew,
    'text': text,
    'color': color,
    'dontFold': dontFold,
    'todoList': todoList,
    'collaborators': collaborators
        .map((c) => {'userId': c.userId, 'right': c.right})
        .toList(),
    'baseUpdatedAt': baseUpdatedAt,
    'localSavedAt': localSavedAt,
  };

  factory PendingNoteEdit.fromJson(Map<String, dynamic> m) => PendingNoteEdit(
    noteId: m['noteId'] as String,
    isNew: m['isNew'] as bool? ?? false,
    text: m['text'] as String,
    color: m['color'] as String?,
    dontFold: m['dontFold'] as bool,
    todoList: m['todoList'] as bool,
    collaborators: (m['collaborators'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(
          (c) => (userId: c['userId'] as String, right: c['right'] as String),
        )
        .toList(),
    baseUpdatedAt: m['baseUpdatedAt'] as String?,
    localSavedAt: m['localSavedAt'] as String,
  );
}
