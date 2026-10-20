import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/domain/routine.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;
  late SqliteWorkoutRepository repo;
  var now = DateTime(2026, 10, 7, 10);
  Future<SqliteWorkoutRepository> open() => SqliteWorkoutRepository.open(
    factory: databaseFactoryFfi,
    path: path,
    clock: () => now,
  );
  setUp(() async {
    now = DateTime(2026, 10, 7, 10);
    dir = await Directory.systemTemp.createTemp('gymia-s2-');
    path = '${dir.path}/test.sqlite';
    repo = await open();
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });
  const squat = RoutineExerciseDraft(
    name: 'Sentadilla',
    targetSets: 3,
    repsMin: 8,
    repsMax: 10,
    restSeconds: 120,
  );
  const row = RoutineExerciseDraft(
    name: 'Remo',
    targetSets: 2,
    repsMin: 10,
    repsMax: 12,
  );

  test(
    'v1 migration preserves active/completed sessions, IDs and sets',
    () async {
      await repo.close();
      await databaseFactoryFfi.deleteDatabase(path);
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            final sql = await File('test/fixtures/sprint1.sql').readAsString();
            for (final statement in sql.split(';')) {
              if (statement.trim().isNotEmpty) await db.execute(statement);
            }
          },
        ),
      );
      for (final id in ['done', 'active']) {
        await old.insert('workouts', {
          'id': id,
          'name': id,
          'started_at': 1000,
          'finished_at': id == 'done' ? 2000 : null,
          'active_slot': id == 'done' ? null : 1,
        });
        await old.insert('exercises', {
          'id': 'e-$id',
          'workout_id': id,
          'name': ' Sentadilla ',
          'position': 0,
        });
        await old.insert('sets', {
          'id': 's-$id',
          'exercise_id': 'e-$id',
          'weight': 6250,
          'reps': 10,
          'position': 0,
        });
      }
      await old.close();
      repo = await open();
      final workouts = await repo.load();
      expect(workouts.length, 2);
      expect(workouts.singleWhere((w) => w.isActive).id, 'active');
      expect(workouts.singleWhere((w) => !w.isActive).id, 'done');
      for (final w in workouts) {
        expect(w.exercises.single.id, 'e-${w.id}');
        expect(w.exercises.single.sets.single.id, 's-${w.id}');
        expect(w.exercises.single.sets.single.weight, 6250);
        expect(w.exercises.single.targetSets, isNull);
        expect(w.exercises.single.sets.single.recordedAt, isNull);
        expect(w.finishedRecordedAt, isNull);
      }
      expect(await repo.loadRoutines(), isEmpty);
      // This fixture intentionally starts both sessions at the same instant.
      await repo.finish('active', acceptTimeConflicts: true);
      expect(
        (await repo.load())
            .singleWhere((w) => w.id == 'active')
            .finishTimeIssues,
        contains('overlap:done'),
      );
      final routineId = await repo.saveRoutine(
        name: 'Pierna',
        exercises: [squat],
      );
      await repo.startRoutine(routineId);
      expect((await repo.load()).length, 3);
    },
  );

  test(
    'routine is durable, ordered and starting copies goals without logging sets',
    () async {
      final id = await repo.saveRoutine(
        name: ' Pierna A ',
        exercises: [squat, row],
      );
      await repo.close();
      repo = await open();
      expect((await repo.loadRoutines()).single.name, 'Pierna A');
      await repo.saveRoutine(
        id: id,
        name: 'Mi rutina',
        exercises: [row, squat],
      );
      final workoutId = await repo.startRoutine(id);
      final w = (await repo.load()).single;
      expect(w.id, workoutId);
      expect(w.exercises.map((e) => e.name), ['Remo', 'Sentadilla']);
      expect(w.exercises.last.targetSets, 3);
      expect(w.exercises.last.repsMax, 10);
      expect(w.exercises.last.restSeconds, 120);
      expect(w.setCount, 0);
      await expectLater(
        repo.finish(workoutId),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        repo.startRoutine(id),
        throwsA(isA<ValidationException>()),
      );
      expect((await repo.load()).length, 1);
    },
  );

  test(
    'editing/deleting routine never changes active session or history',
    () async {
      final id = await repo.saveRoutine(name: 'Original', exercises: [squat]);
      final first = await repo.startRoutine(id);
      final e = (await repo.load()).single.exercises.single;
      await repo.addSet(e.id, '60', '10');
      await repo.saveRoutine(id: id, name: 'Changed', exercises: [row]);
      expect((await repo.load()).single.name, 'Original');
      expect((await repo.load()).single.exercises.single.name, 'Sentadilla');
      await repo.finish(first);
      final second = await repo.startRoutine(id);
      await repo.deleteRoutine(id);
      final workouts = await repo.load();
      expect(workouts.singleWhere((w) => w.id == first).setCount, 1);
      expect(
        workouts.singleWhere((w) => w.id == second).exercises.single.name,
        'Remo',
      );
      expect(await repo.loadRoutines(), isEmpty);
      await repo.addSet(
        workouts.singleWhere((w) => w.id == second).exercises.single.id,
        '20',
        '12',
      );
      await repo.finish(second);
    },
  );

  test('invalid routine edits leave the stored routine unchanged', () async {
    final id = await repo.saveRoutine(name: 'Original', exercises: [squat]);
    await expectLater(
      repo.saveRoutine(id: id, name: 'Invalid', exercises: []),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repo.saveRoutine(
        id: id,
        name: 'Invalid',
        exercises: [
          const RoutineExerciseDraft(name: 'A', repsMin: 12, repsMax: 8),
        ],
      ),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo.loadRoutines()).single.name, 'Original');
  });

  test(
    'previous performance uses completed matching exercises, skips empty newer sessions',
    () async {
      final first = await repo.start('Anterior');
      await repo.addExercise(first, 'Press  banca');
      await repo.addSet(
        (await repo.load()).first.exercises.first.id,
        '40',
        '10',
      );
      await repo.finish(first);
      now = now.add(const Duration(hours: 1));
      final empty = await repo.start('Sin banca');
      await repo.addExercise(empty, 'Press banca');
      await repo.addExercise(empty, 'Remo');
      await repo.addSet(
        (await repo.load()).first.exercises.last.id,
        '20',
        '12',
      );
      await repo.finish(empty);
      now = now.add(const Duration(days: 1));
      final current = await repo.start('Actual');
      await repo.addExercise(current, 'PRESS BANCA');
      final c = WorkoutController(repo);
      await c.refresh();
      final previous = c.previousFor(c.active!.exercises.single, c.active!);
      expect(previous!.sets.single.weight, 4000);
      expect(previous.sets.single.reps, 10);
      await repo.addSet(c.active!.exercises.single.id, '80', '6');
      await c.refresh();
      expect(
        c
            .previousFor(c.active!.exercises.single, c.active!)!
            .sets
            .single
            .weight,
        4000,
      );
      c.dispose();
    },
  );

  test(
    'rest timer pauses, survives reopening, resumes and expires without drift',
    () async {
      final id = await repo.start('A');
      await repo.startRest(id, 90);
      now = now.add(const Duration(seconds: 20, milliseconds: 250));
      expect((await repo.loadRestTimer())!.remainingAt(now), 69750);
      await repo.pauseRest(id);
      now = now.add(const Duration(hours: 1));
      await repo.close();
      repo = await open();
      expect((await repo.loadRestTimer())!.remainingAt(now), 69750);
      await repo.resumeRest(id);
      now = now.add(const Duration(seconds: 60));
      await repo.close();
      repo = await open();
      expect((await repo.loadRestTimer())!.remainingAt(now), 9750);
      now = now.add(const Duration(minutes: 10));
      expect((await repo.loadRestTimer())!.remainingAt(now), 0);
      await repo.resetRest(id, 120);
      expect((await repo.loadRestTimer())!.endsAt, isNull);
      expect((await repo.loadRestTimer())!.remainingAt(now), 120000);
    },
  );

  test(
    'finishing/discarding session clears timer; closed sessions cannot start it',
    () async {
      final id = await repo.start('A');
      await repo.addExercise(id, 'Remo');
      await repo.addSet(
        (await repo.load()).single.exercises.single.id,
        '20',
        '10',
      );
      await repo.startRest(id, 60);
      await repo.finish(id);
      expect(await repo.loadRestTimer(), isNull);
      await expectLater(
        repo.startRest(id, 60),
        throwsA(isA<ValidationException>()),
      );
      final next = await repo.start('B');
      await repo.startRest(next, 60);
      await repo.discard(next);
      expect(await repo.loadRestTimer(), isNull);
    },
  );
}
