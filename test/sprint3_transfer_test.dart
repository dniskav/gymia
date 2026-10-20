import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/routine.dart';
import 'package:gymia/domain/transfer.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late String path;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gymia-s3-');
    path = '${dir.path}/db.sqlite';
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  test(
    'backup restores history, active session, routines, sets and timer',
    () async {
      final first = await repo.start('Lunes');
      await repo.addExercise(first, 'Remo');
      final exercise = (await repo.load()).single.exercises.single;
      await repo.addSet(exercise.id, '42,5', '8');
      await repo.finish(first);
      final routine = await repo.saveRoutine(
        name: 'Pierna',
        exercises: [const RoutineExerciseDraft(name: 'Sentadilla')],
      );
      final active = await repo.startRoutine(routine);
      await repo.startRest(active, 90);
      final backup = await repo.createBackupJson();
      expect(repo.inspectBackupJson(backup).active, isTrue);
      await repo.discard(active);
      await repo.deleteRoutine(routine);
      await repo.restoreBackupJson(backup);
      final restored = await repo.load();
      expect(restored.length, 2);
      expect(restored.singleWhere((w) => w.isActive).id, active);
      expect(
        restored
            .singleWhere((w) => !w.isActive)
            .exercises
            .single
            .sets
            .single
            .weight,
        4250,
      );
      expect((await repo.loadRoutines()).single.id, routine);
      expect((await repo.loadRestTimer())?.workoutId, active);
      expect(jsonDecode(await repo.createBackupJson()), jsonDecode(backup));
      await repo.close();
      repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await repo.load()).length, 2);
    },
  );

  test('bad backup rolls back without losing current data', () async {
    final id = await repo.start('Importante');
    final source =
        jsonDecode(await repo.createBackupJson()) as Map<String, dynamic>;
    final tables = source['tables'] as Map<String, dynamic>;
    final exercises = tables['exercises'] as List;
    exercises.add({
      'id': 'orphan',
      'workout_id': 'missing',
      'name': 'X',
      'position': 0,
      'exercise_key': 'x',
      'target_sets': null,
      'reps_min': null,
      'reps_max': null,
      'rest_seconds': 90,
    });
    await expectLater(
      repo.restoreBackupJson(jsonEncode(source)),
      throwsA(isA<Exception>()),
    );
    expect((await repo.load()).single.id, id);
    await expectLater(
      repo.restoreBackupJson('{"format":"wrong"}'),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo.load()).single.id, id);
    final wrongType =
        jsonDecode(await repo.createBackupJson()) as Map<String, dynamic>;
    ((wrongType['tables'] as Map)['workouts'] as List).single['started_at'] =
        'ayer';
    await expectLater(
      repo.restoreBackupJson(jsonEncode(wrongType)),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo.load()).single.id, id);
  });

  test('CSV maps columns, reports bad rows and import is idempotent', () async {
    final csv =
        'Ejercicio;Reps;Fecha;Peso;Sesión\n"Press, banca";8;06/10/2026;60,5;Empuje\n"Press, banca";7;06/10/2026;60,5;Empuje\nRemo;10;07/10/2026;40;Tirón\nRemo;0;07/10/2026;40;Tirón';
    final sheet = CsvSheet.parse(csv);
    final preview = sheet.preview(sheet.suggestedMapping());
    expect(preview.workouts.length, 2);
    expect(preview.validRows, 3);
    expect(preview.errors.single, contains('Fila 5'));
    final first = await repo.importWorkouts(preview.workouts);
    expect(first.added, 2);
    final second = await repo.importWorkouts(preview.workouts);
    expect(second.added, 0);
    expect(second.duplicates, 2);
    expect((await repo.load()).length, 2);
    expect((await repo.load()).first.exercises.single.sets.single.weight, 4000);
  });

  test('CSV rejects missing mapping and invalid file', () {
    final sheet = CsvSheet.parse(
      'Fecha,Ejercicio,Peso,Reps\n2026-10-07,Remo,20,8',
    );
    expect(sheet.preview(sheet.suggestedMapping()).validRows, 1);
    expect(
      () => sheet.preview(
        const CsvMapping(date: 0, exercise: 0, weight: 2, reps: 3),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(() => CsvSheet.parse('a,b'), throwsA(isA<ValidationException>()));
  });

  test('Excel copy opens valid tabs and reads dates and series', () async {
    final bytes = await File('test/fixtures/sprint3-sheets.xlsx').readAsBytes();
    final document = SheetDocument.decode(bytes);
    expect(document.tabs.keys, ['Histórico', 'Otro']);
    final sheet = document.tabs['Histórico']!;
    final preview = sheet.preview(sheet.suggestedMapping());
    expect(preview.workouts.single.setCount, 2);
    expect(preview.workouts.single.date, DateTime(2026, 10, 7, 10, 30));
    expect(preview.workouts.single.exercises.single.sets.first.weight, 6050);
    expect(parseCsvDate('46302').year, greaterThan(2025));
  });
}
