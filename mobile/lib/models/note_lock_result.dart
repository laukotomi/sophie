class NoteLockResult {
  final String text;
  final DateTime updatedAt;

  NoteLockResult({required this.text, required this.updatedAt});

  factory NoteLockResult.fromJson(Map<String, dynamic> json) {
    return NoteLockResult(
      text: json['text'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
