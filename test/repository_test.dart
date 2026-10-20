import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late String dbPath;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gymia-test-');
    dbPath = '${dir.path}/test.sqlite';
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: dbPath,
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<String> exercise() async {
    final id = await repo.start('Fuerza');
    await repo.addExercise(id, 'Sentadilla');
    return (await repo.load()).single.exercises.single.id;
  }

  test(
    'persists active session and sets after closing and reopening database',
    () async {
      final e = await exercise();
      await repo.addSet(e, '62,50', '10');
      await repo.close();
      repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      final w = (await repo.load()).single;
      expect(w.isActive, isTrue);
      expect(w.name, 'Fuerza');
      expect(w.exercises.single.sets.single.weight, 6250);
      expect(w.exercises.single.sets.single.reps, 10);
      await repo.finish(w.id);
      await repo.close();
      repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: dbPath,
      );
      expect((await repo.load()).single.isActive, isFalse);
    },
  );

  test('concurrent starts create only one active workout', () async {
    final result = await Future.wait([
      repo.start('A').then((_) => true).catchError((_) => false),
      repo.start('B').then((_) => true).catchError((_) => false),
    ]);
    expect(result.where((x) => x).length, 1);
    expect((await repo.load()).length, 1);
  });

  test(
    'editing and deleting target only selected set and preserve order',
    () async {
      final e = await exercise();
      await repo.addSet(e, '20', '8');
      await repo.addSet(e, '25', '6');
      final original = (await repo.load()).single.exercises.single.sets;
      await repo.editSet(original.first.id, '22,5', '9');
      var sets = (await repo.load()).single.exercises.single.sets;
      expect(sets.first.weight, 2250);
      expect(sets.last.weight, 2500);
      await repo.deleteSet(original.first.id);
      await repo.addSet(e, '30', '5');
      sets = (await repo.load()).single.exercises.single.sets;
      expect(sets.map((s) => s.weight), [2500, 3000]);
      expect(sets.first.id, original.last.id);
    },
  );

  test('invalid input does not write or mutate existing values', () async {
    final e = await exercise();
    await expectLater(
      repo.addSet(e, '-1', '10'),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      repo.addSet(e, '20', '0'),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo.load()).single.setCount, 0);
    await repo.addSet(e, '0', '12');
    final id = (await repo.load()).single.exercises.single.sets.single.id;
    await expectLater(
      repo.editSet(id, 'NaN', '8'),
      throwsA(isA<ValidationException>()),
    );
    expect((await repo.load()).single.exercises.single.sets.single.reps, 12);
  });

  test(
    'cannot finish empty session and completed history is immutable',
    () async {
      final e = await exercise();
      final id = (await repo.load()).single.id;
      await expectLater(repo.finish(id), throwsA(isA<ValidationException>()));
      await repo.addSet(e, '40', '8');
      await repo.finish(id);
      await expectLater(
        repo.addSet(e, '50', '10'),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(repo.discard(id), throwsA(isA<ValidationException>()));
      await repo.start('Siguiente');
      expect((await repo.load()).where((w) => w.isActive).length, 1);
      expect((await repo.load()).where((w) => !w.isActive).length, 1);
    },
  );

  test(
    'exercise removal and session discard cascade without affecting another workout',
    () async {
      final e = await exercise();
      await repo.addSet(e, '20', '10');
      final first = (await repo.load()).single.id;
      await repo.finish(first);
      final second = await repo.start('Segunda');
      await repo.addExercise(second, 'Remo');
      final secondExercise = (await repo.load()).first.exercises.single.id;
      await repo.addSet(secondExercise, '30', '8');
      await repo.deleteExercise(secondExercise);
      expect((await repo.load()).first.setCount, 0);
      await repo.discard(second);
      expect((await repo.load()).single.id, first);
      expect((await repo.load()).single.setCount, 1);
    },
  );
}
