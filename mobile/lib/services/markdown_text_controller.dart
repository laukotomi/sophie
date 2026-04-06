import 'package:flutter/material.dart';

class MarkdownTextController extends TextEditingController {
  MarkdownTextController({super.text});

  // Matches numbered list prefixes: "1. ", "12. ", etc. — captures the number separately.
  final _numberedPattern = RegExp(r'^(\s*)(\d+)(\.)\s+');
  // Matches bullet/blockquote prefixes: "- ", "* ", "> "
  final _bulletPattern = RegExp(r'^(\s*(?:[-*>])\s+)');

  String? _nextPrefix(String line) {
    final numMatch = _numberedPattern.firstMatch(line);
    if (numMatch != null) {
      final indent = numMatch.group(1)!;
      final n = int.parse(numMatch.group(2)!);
      final dot = numMatch.group(3)!;
      return '$indent${n + 1}$dot ';
    }
    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) return bulletMatch.group(1)!;
    return null;
  }

  @override
  set value(TextEditingValue newValue) {
    final old = value;
    // Detect a newline being inserted
    if (newValue.text.length == old.text.length + 1 &&
        newValue.text[newValue.selection.baseOffset - 1] == '\n') {
      final cursor = newValue.selection.baseOffset;
      final textBefore = newValue.text.substring(0, cursor);
      final lineStart = textBefore.lastIndexOf('\n', cursor - 2) + 1;
      final prevLine = textBefore.substring(lineStart, cursor - 1);
      final prefix = _nextPrefix(prevLine);
      if (prefix != null) {
        // If the previous line had only the prefix (empty item), remove it instead
        final matchLen =
            (_numberedPattern.firstMatch(prevLine) ??
                    _bulletPattern.firstMatch(prevLine))!
                .group(0)!
                .length;
        final isEmpty = prevLine.length == matchLen;
        if (isEmpty) {
          final cleaned =
              old.text.substring(0, lineStart) + old.text.substring(cursor - 1);
          super.value = TextEditingValue(
            text: cleaned,
            selection: TextSelection.collapsed(offset: lineStart),
          );
          return;
        }
        final inserted =
            newValue.text.substring(0, cursor) +
            prefix +
            newValue.text.substring(cursor);
        super.value = TextEditingValue(
          text: inserted,
          selection: TextSelection.collapsed(offset: cursor + prefix.length),
        );
        return;
      }
    }
    super.value = newValue;
  }
}
