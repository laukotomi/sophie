import 'package:flutter/material.dart';

/// Shared color palette used for both notes and tasks.
/// null represents the default theme surface colour.
const kNotePalette = <String?>[
  null,
  '#B71C1C', // red
  '#E65100', // orange
  '#F9A825', // yellow
  '#1B5E20', // green
  '#006064', // cyan
  '#0D47A1', // blue
  '#4A148C', // purple
  '#880E4F', // pink
  '#4E342E', // brown
];

/// Converts a hex colour string (e.g. `#B71C1C`) to a [Color].
Color hexToColor(String hex) =>
    Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Returns black or white depending on which contrasts better with [hex].
Color noteContrastColor(String hex) {
  final luminance = hexToColor(hex).computeLuminance();
  return luminance > 0.35 ? Colors.black87 : Colors.white;
}
