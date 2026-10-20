import 'dart:convert';
import 'activity.dart';
import 'workout.dart';

/// A closed, original local snapshot. Chat summaries are never an export source.
Map<String, dynamic> sheetWorkoutSource(
  Workout workout,
  List<FocusActivity> all,
) => {
  'id': workout.id,
  'name': workout.name,
  'startedAt': workout.startedAt.toIso8601String(),
  'finishedAt': workout.finishedAt?.toIso8601String(),
  'finishTimeIssues': workout.finishTimeIssues,
  'exercises': [
    for (final e in workout.exercises)
      {
        'id': e.id,
        'name': e.name,
        'sets': [
          for (final s in e.sets)
            {
              'id': s.id,
              'kg': s.weight / 100,
              'reps': s.reps,
              'recordedAt': s.recordedAt?.toIso8601String(),
            },
        ],
      },
  ],
  'activities': [
    for (final a in all.where(
      (a) =>
          a.workoutId == workout.id && !a.finishIssues.contains('not_started'),
    ))
      {
        ...a.toJson(),
        'exerciseId': a.exerciseId,
        'draft': a.draft,
        'messages': [
          for (final m in a.messages.where((m) => m.role == 'user')) m.toJson(),
        ],
      },
  ],
};

class SheetCellWrite {
  const SheetCellWrite(this.row, this.column, this.value);
  final int row, column; // zero based
  final Object value;
  String get address {
    var c = column + 1;
    var letters = '';
    while (c > 0) {
      c--;
      letters = String.fromCharCode(65 + c % 26) + letters;
      c ~/= 26;
    }
    return '$letters${row + 1}';
  }

  Map<String, dynamic> toJson() => {
    'row': row,
    'column': column,
    'value': value,
  };
}

class SheetClarification implements Exception {
  const SheetClarification(this.question);
  final String question;
}

class SheetSyncPlan {
  const SheetSyncPlan(this.writes, this.summary, {this.layout = ''});
  final String layout;
  final List<SheetCellWrite> writes;
  final String summary;
  static SheetSyncPlan parse(
    String response,
    Map<String, dynamic> snapshot, {
    bool allowOverwrite = false,
    String fence = 'gymia-sheet-plan',
    bool requireExpected = false,
  }) {
    final matches =
        RegExp('```$fence\\s*\\n([\\s\\S]*?)```').allMatches(response).toList();
    if (matches.isEmpty &&
        !response.contains('```$fence') &&
        response.trim().isNotEmpty) {
      throw SheetClarification(response.trim());
    }
    if (matches.length != 1) {
      throw const ValidationException(
        'El modelo no preparó un envío válido. Aclara la zona o el formato de la hoja y vuelve a preparar.',
      );
    }
    try {
      final json = jsonDecode(matches.single[1]!) as Map<String, dynamic>;
      if (json.keys.toSet().difference({
        'summary',
        'writes',
        'layout',
      }).isNotEmpty) {
        throw const FormatException();
      }
      final summary = json['summary'] as String;
      if (summary.isEmpty || summary.length > 1500) {
        throw const FormatException();
      }
      final layout = json['layout'] as String? ?? '';
      if (layout.length > 3000) throw const FormatException();
      final raw = json['writes'] as List;
      if (raw.isEmpty || raw.length > 250) throw const FormatException();
      final properties = Map<String, dynamic>.from(
        snapshot['properties'] as Map,
      );
      final grid = Map<String, dynamic>.from(
        properties['gridProperties'] as Map,
      );
      final occupied = (snapshot['occupied'] as List).toSet();
      final seen = <String>{};
      final writes = <SheetCellWrite>[];
      for (final item in raw) {
        final cell = Map<String, dynamic>.from(item as Map);
        if (cell.keys.toSet().difference({
              'cell',
              'value',
              if (requireExpected) 'expected',
            }).isNotEmpty ||
            requireExpected && cell['expected'] is! String) {
          throw const FormatException();
        }
        final address = cell['cell'] as String;
        final match = RegExp(
          r'^([A-Z]{1,3})([1-9][0-9]{0,6})$',
        ).firstMatch(address);
        if (match == null || !seen.add(address)) throw const FormatException();
        var column = 0;
        for (final c in match[1]!.codeUnits) {
          column = column * 26 + c - 64;
        }
        column--;
        final row = int.parse(match[2]!) - 1;
        if (row >= (grid['rowCount'] as int) ||
            column >= (grid['columnCount'] as int)) {
          throw const FormatException();
        }
        if (requireExpected) {
          final rows = snapshot['rows'] as List;
          final actual =
              row < rows.length && column < (rows[row] as List).length
                  ? (rows[row] as List)[column].toString()
                  : '';
          if (actual != cell['expected']) {
            throw ValidationException(
              '$address cambió desde la lectura del chat. Pide al asistente que lea de nuevo antes de modificar.',
            );
          }
        }
        final entered = snapshot['entered'] as Map? ?? {};
        final before = entered['$row:$column'] as Map?;
        if (before?.containsKey('formulaValue') == true) {
          throw ValidationException(
            '$address contiene una fórmula. No se modifica.',
          );
        }
        if (occupied.contains('$row:$column') &&
            (!allowOverwrite || before == null)) {
          throw ValidationException(
            'El modelo intentó escribir en $address, que ya contiene datos. No se ha enviado nada.',
          );
        }
        for (final rawMerge in snapshot['merges'] as List) {
          final m = Map<String, dynamic>.from(rawMerge as Map);
          if (row >= (m['startRowIndex'] as int? ?? 0) &&
              row < (m['endRowIndex'] as int) &&
              column >= (m['startColumnIndex'] as int? ?? 0) &&
              column < (m['endColumnIndex'] as int)) {
            throw ValidationException(
              '$address está combinada con otras celdas. Elige otra zona.',
            );
          }
        }
        final value = cell['value'];
        if (!(value is String && value.isNotEmpty && value.length <= 4000 ||
            value is num && value.isFinite ||
            value is bool)) {
          throw const FormatException();
        }
        writes.add(SheetCellWrite(row, column, value as Object));
      }
      return SheetSyncPlan(List.unmodifiable(writes), summary, layout: layout);
    } on ValidationException {
      rethrow;
    } catch (_) {
      throw const ValidationException(
        'La propuesta contiene celdas o valores no válidos. No se ha enviado nada.',
      );
    }
  }
}

Map<String, dynamic>? sheetSyncDirective(String answer) {
  final matches =
      RegExp(r'```gymia-sync\s*\n([\s\S]*?)```').allMatches(answer).toList();
  if (matches.length != 1) return null;
  try {
    final json = jsonDecode(matches.single[1]!) as Map<String, dynamic>;
    if (json.keys.toSet().difference({
          'workoutId',
          'create',
          'name',
        }).isNotEmpty ||
        json['workoutId'] is! String ||
        json['create'] != null && json['create'] is! bool ||
        json['name'] != null &&
            (json['name'] is! String || (json['name'] as String).length > 80)) {
      return null;
    }
    return json;
  } catch (_) {
    return null;
  }
}
