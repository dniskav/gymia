import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'workout.dart';
import 'routine.dart';

class CsvMapping {
  const CsvMapping({
    required this.date,
    required this.exercise,
    required this.weight,
    required this.reps,
    this.session,
  });
  final int date, exercise, weight, reps;
  final int? session;
  bool get valid =>
      {date, exercise, weight, reps, if (session != null) session!}.length ==
      (session == null ? 4 : 5);
}

class ImportedSet {
  const ImportedSet(this.weight, this.reps);
  final int weight, reps;
}

class ImportedExercise {
  ImportedExercise(this.name);
  final String name;
  final List<ImportedSet> sets = [];
}

class ImportedWorkout {
  ImportedWorkout(this.name, this.date);
  final String name;
  final DateTime date;
  final List<ImportedExercise> exercises = [];
  int get setCount => exercises.fold(0, (n, e) => n + e.sets.length);
}

class CsvPreview {
  CsvPreview(this.workouts, this.errors, this.totalRows);
  final List<ImportedWorkout> workouts;
  final List<String> errors;
  final int totalRows;
  int get validRows => workouts.fold(0, (n, w) => n + w.setCount);
}

class CsvSheet {
  CsvSheet._(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;

  static CsvSheet fromCells(List<List<dynamic>> cells) {
    if (cells.isEmpty) {
      throw const ValidationException('La pestaña está vacía.');
    }
    final headers =
        cells.first.map((v) => v == null ? '' : '$v'.trim()).toList();
    if (headers.length < 4 || headers.every((h) => h.isEmpty)) {
      throw const ValidationException(
        'La pestaña necesita encabezados y al menos cuatro columnas.',
      );
    }
    final rows =
        cells
            .skip(1)
            .map((row) => row.map((v) => v == null ? '' : '$v').toList())
            .where((row) => row.any((v) => v.trim().isNotEmpty))
            .toList();
    return CsvSheet._(headers, rows);
  }

  static CsvSheet parse(String raw) {
    if (raw.length > 20 * 1024 * 1024) {
      throw const ValidationException('El CSV supera 20 MB.');
    }
    final normalized = raw
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final firstLine = normalized.split('\n').first;
    final separator =
        ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
            ? ';'
            : ',';
    late final List<List<dynamic>> parsed;
    try {
      parsed = CsvToListConverter(
        fieldDelimiter: separator,
        eol: '\n',
        shouldParseNumbers: false,
        allowInvalid: false,
      ).convert(normalized);
    } catch (_) {
      throw const ValidationException(
        'El CSV tiene comillas o separadores incorrectos.',
      );
    }
    if (parsed.isEmpty) throw const ValidationException('El CSV está vacío.');
    return fromCells(parsed);
  }

  CsvMapping suggestedMapping() {
    int find(List<String> names) {
      for (var i = 0; i < headers.length; i++) {
        final h = headers[i].toLowerCase().replaceAll(
          RegExp(r'[^a-záéíóúüñ0-9]'),
          '',
        );
        if (names.any((n) => h.contains(n))) return i;
      }
      return -1;
    }

    return CsvMapping(
      date: find(['fecha', 'date', 'dia']),
      session: switch (find([
        'sesion',
        'sesión',
        'entrenamiento',
        'workout',
        'rutina',
      ])) {
        -1 => null,
        final n => n,
      },
      exercise: find(['ejercicio', 'exercise', 'movimiento']),
      weight: find(['peso', 'weight', 'kg', 'carga']),
      reps: find(['repeticiones', 'reps', 'rep']),
    );
  }

  CsvPreview preview(CsvMapping mapping) {
    if ([
          mapping.date,
          mapping.exercise,
          mapping.weight,
          mapping.reps,
        ].any((n) => n < 0 || n >= headers.length) ||
        !mapping.valid ||
        (mapping.session != null &&
            (mapping.session! < 0 || mapping.session! >= headers.length))) {
      throw const ValidationException(
        'Asigna una columna distinta a cada dato obligatorio.',
      );
    }
    final workouts = <String, ImportedWorkout>{};
    final errors = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      String field(int index) => index < row.length ? row[index].trim() : '';
      try {
        final date = parseCsvDate(field(mapping.date));
        final name = validName(
          mapping.session == null || field(mapping.session!).isEmpty
              ? 'Entrenamiento'
              : field(mapping.session!),
        );
        final exercise = validName(field(mapping.exercise));
        final weight = parseWeight(field(mapping.weight));
        final reps = parseReps(field(mapping.reps));
        final key = '${date.millisecondsSinceEpoch}|${name.toLowerCase()}';
        final workout = workouts.putIfAbsent(
          key,
          () => ImportedWorkout(name, date),
        );
        final item =
            workout.exercises
                .where((e) => exerciseKey(e.name) == exerciseKey(exercise))
                .firstOrNull ??
            (ImportedExercise(exercise)..alsoAddTo(workout.exercises));
        item.sets.add(ImportedSet(weight, reps));
      } on ValidationException catch (e) {
        errors.add('Fila ${i + 2}: ${e.message}');
      }
    }
    return CsvPreview(workouts.values.toList(), errors, rows.length);
  }
}

class SheetDocument {
  SheetDocument(this.tabs);
  final Map<String, CsvSheet> tabs;

  /// Decode cells independently of any workout schema. Blank rows/columns
  /// remain in place so the model can refer to original coordinates.
  static Map<String, List<List<String>>> decodeCells(Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const ValidationException('La hoja supera 20 MB.');
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      try {
        final workbook = xlsx.Excel.decodeBytes(
          _normalizeXlsxRelationships(bytes),
        );
        final tabs = <String, List<List<String>>>{};
        for (final entry in workbook.tables.entries) {
          final rows = [
            for (final row in entry.value.rows)
              [for (final cell in row) _excelValue(cell?.value)],
          ];
          if (rows.any((r) => r.any((c) => c.trim().isNotEmpty))) {
            tabs[entry.key] = rows;
          }
        }
        if (tabs.isEmpty) throw const FormatException();
        return tabs;
      } catch (_) {
        throw const ValidationException(
          'No se pudo leer la copia Excel. Elige un archivo XLSX o CSV válido.',
        );
      }
    }
    try {
      final raw = utf8
          .decode(bytes)
          .replaceFirst('\uFEFF', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final first = raw
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty);
      final separator =
          ';'.allMatches(first).length > ','.allMatches(first).length
              ? ';'
              : ',';
      final rows = CsvToListConverter(
        fieldDelimiter: separator,
        eol: '\n',
        shouldParseNumbers: false,
        allowInvalid: false,
      ).convert(raw);
      if (!rows.any((r) => r.any((c) => c.toString().trim().isNotEmpty))) {
        throw const FormatException();
      }
      return {
        'CSV': [
          for (final row in rows) [for (final cell in row) cell.toString()],
        ],
      };
    } catch (_) {
      throw const ValidationException(
        'No se pudo leer esa hoja. Elige una copia XLSX o CSV válida.',
      );
    }
  }

  static SheetDocument decode(Uint8List bytes) {
    if (bytes.length > 20 * 1024 * 1024) {
      throw const ValidationException('La hoja supera 20 MB.');
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      try {
        final workbook = xlsx.Excel.decodeBytes(
          _normalizeXlsxRelationships(bytes),
        );
        final tabs = <String, CsvSheet>{};
        for (final entry in workbook.tables.entries) {
          if (entry.value.rows.isEmpty) continue;
          try {
            tabs[entry.key] = CsvSheet.fromCells([
              for (final row in entry.value.rows)
                [for (final cell in row) _excelValue(cell?.value)],
            ]);
          } on ValidationException {
            // Ignore notes or dashboards; the user chooses a data tab below.
          }
        }
        if (tabs.isEmpty) throw const FormatException();
        return SheetDocument(tabs);
      } catch (_) {
        throw const ValidationException(
          'No se pudo leer la copia Excel. Exporta la hoja como XLSX o CSV.',
        );
      }
    }
    try {
      return SheetDocument({'CSV': CsvSheet.parse(utf8.decode(bytes))});
    } catch (_) {
      throw const ValidationException(
        'No se pudo leer esa hoja. En Google Sheets usa «Enviar una copia» como Excel o CSV y elige GymIA.',
      );
    }
  }

  static String _excelValue(xlsx.CellValue? value) => switch (value) {
    xlsx.DateCellValue v => v.asDateTimeLocal().toIso8601String(),
    xlsx.DateTimeCellValue v => v.asDateTimeLocal().toIso8601String(),
    null => '',
    _ => value.toString(),
  };

  // Some workbook writers use absolute worksheet targets; excel expects
  // targets relative to /xl. Normalize those links before decoding.
  static List<int> _normalizeXlsxRelationships(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final relationships = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relationships == null) return bytes;
    final xml = utf8.decode(relationships.content as List<int>);
    final normalized = xml.replaceAllMapped(
      RegExp(r'''Target=["']/xl/([^"']+)["']'''),
      (match) => 'Target="${match[1]}"',
    );
    if (normalized == xml) return bytes;
    final fixed = Archive();
    for (final file in archive.files) {
      if (file.name == relationships.name) {
        final content = utf8.encode(normalized);
        fixed.addFile(ArchiveFile(file.name, content.length, content));
      } else {
        fixed.addFile(file);
      }
    }
    return ZipEncoder().encode(fixed)!;
  }
}

extension _AddExercise on ImportedExercise {
  ImportedExercise alsoAddTo(List<ImportedExercise> list) {
    list.add(this);
    return this;
  }
}

DateTime parseCsvDate(String input) {
  final raw = input.trim();
  final excelSerial = double.tryParse(raw);
  if (excelSerial != null && excelSerial >= 20000 && excelSerial <= 80000) {
    return DateTime(
      1899,
      12,
      30,
    ).add(Duration(milliseconds: (excelSerial * 86400000).round()));
  }
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;
  for (final pattern in [
    'd/M/yyyy H:mm',
    'd/M/yyyy',
    'd-M-yyyy H:mm',
    'd-M-yyyy',
    'yyyy/M/d H:mm',
    'yyyy/M/d',
  ]) {
    try {
      return DateFormat(pattern).parseStrict(raw);
    } catch (_) {}
  }
  throw const ValidationException(
    'Fecha no reconocida. Usa DD/MM/AAAA o AAAA-MM-DD.',
  );
}

String importedFingerprint(ImportedWorkout w) => jsonEncode([
  w.date.year,
  w.date.month,
  w.date.day,
  w.date.hour,
  w.date.minute,
  w.name.trim().toLowerCase(),
  for (final e in w.exercises)
    [
      exerciseKey(e.name),
      for (final s in e.sets) [s.weight, s.reps],
    ],
]);

String workoutFingerprint(Workout w) => jsonEncode([
  w.startedAt.year,
  w.startedAt.month,
  w.startedAt.day,
  w.startedAt.hour,
  w.startedAt.minute,
  w.name.trim().toLowerCase(),
  for (final e in w.exercises)
    [
      exerciseKey(e.name),
      for (final s in e.sets) [s.weight, s.reps],
    ],
]);
