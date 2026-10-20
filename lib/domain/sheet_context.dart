import 'dart:convert';
import 'workout.dart';

/// A complete, dated copy of one tab. Cells retain their original positions
/// and displayed text; interpreting them never mutates workout records.
class SheetContext {
  SheetContext({
    required this.id,
    required this.name,
    required this.title,
    required this.loadedAt,
    required List<List<String>> rows,
    this.source = 'google',
    this.interpretationPending = true,
  }) : rows = List.unmodifiable(rows.map((r) => List<String>.unmodifiable(r))) {
    if (id.isEmpty ||
        title.isEmpty ||
        !rows.any((r) => r.any((c) => c.trim().isNotEmpty))) {
      throw const ValidationException('La pestaña está vacía o no es válida.');
    }
    if (utf8.encode(jsonEncode(toJson())).length > 120000) {
      throw const ValidationException(
        'Esta pestaña es demasiado grande para cargarla completa en el chat. Elige una pestaña más pequeña; no se ha recortado ni cargado parcialmente.',
      );
    }
  }

  final String id, name, title;
  final DateTime loadedAt;
  final List<List<String>> rows;
  final String source;
  final bool interpretationPending;
  SheetContext interpreted() => SheetContext(
    id: id,
    name: name,
    title: title,
    loadedAt: loadedAt,
    rows: rows,
    source: source,
    interpretationPending: false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'title': title,
    'loadedAt': loadedAt.toIso8601String(),
    'rows': rows,
    'source': source,
    'interpretationPending': interpretationPending,
  };

  factory SheetContext.fromJson(Map<String, dynamic> json) => SheetContext(
    id: json['id'] as String,
    name: json['name'] as String,
    title: json['title'] as String,
    loadedAt: DateTime.parse(json['loadedAt'] as String),
    source: json['source'] as String? ?? 'google',
    interpretationPending: json['interpretationPending'] as bool? ?? true,
    rows: [
      for (final row in json['rows'] as List)
        [for (final cell in row as List) cell as String],
    ],
  );
}
