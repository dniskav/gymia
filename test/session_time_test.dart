import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  var now = DateTime(2026, 10, 8, 8);
  Future<SqliteWorkoutRepository> open() => SqliteWorkoutRepository.open(
    factory: databaseFactoryFfi,
    path: '${dir.path}/db.sqlite',
    clock: () => now,
  );
  setUp(() async {
    now = DateTime(2026, 10, 8, 8);
    dir = await Directory.systemTemp.createTemp('gymia-times-');
    repo = await open();
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<String> session(String name) async {
    final id = await repo.start(name);
    await repo.addExercise(id, 'Chest Press');
    final exercise =
        (await repo.load()).singleWhere((w) => w.id == id).exercises.single;
    now = DateTime(2026, 10, 8, 11);
    await repo.addSet(exercise.id, '60', '13');
    return id;
  }

  test(
    'forgotten closure uses user time, records actual save time, preserves series capture',
    () async {
      final id = await session('Mañana');
      now = DateTime(2026, 10, 8, 17);
      final chosen = DateTime(2026, 10, 8, 11, 30);
      await repo.finish(id, finishedAt: chosen);
      await repo.close();
      repo = await open();
      final w = (await repo.load()).single;
      expect(w.finishedAt, chosen);
      expect(w.finishedRecordedAt, now);
      expect(w.finishTimeSource, FinishTimeSource.user);
      expect(w.finishTimeIssues, isEmpty);
      expect(
        w.exercises.single.sets.single.recordedAt,
        DateTime(2026, 10, 8, 11),
      );
    },
  );

  test(
    'time before last record requires acknowledgement then survives backup without repair',
    () async {
      final id = await session('Mañana');
      now = DateTime(2026, 10, 8, 17);
      await repo.startRest(id, 90);
      final chosen = DateTime(2026, 10, 8, 10);
      await expectLater(
        repo.finish(id, finishedAt: chosen),
        throwsA(isA<ValidationException>()),
      );
      expect((await repo.load()).single.isActive, isTrue);
      expect(await repo.loadRestTimer(), isNotNull);
      await repo.finish(id, finishedAt: chosen, acceptTimeConflicts: true);
      final w = (await repo.load()).single;
      expect(w.finishedAt, chosen);
      expect(w.finishTimeIssues, ['before_last_record']);
      expect(w.finishedRecordedAt, now);
      expect(w.exercises.single.sets.single.reps, 13);
      expect(
        w.exercises.single.sets.single.recordedAt,
        DateTime(2026, 10, 8, 11),
      );
      final backup = await repo.createBackupJson();
      await repo.restoreBackupJson(backup);
      expect(jsonDecode(await repo.createBackupJson()), jsonDecode(backup));
      expect((await repo.load()).single.finishedAt, chosen);
      expect(await repo.loadRestTimer(), isNull);
    },
  );

  test(
    'old format 1 backup keeps timestamps unknown and can be restored',
    () async {
      await session('Anterior');
      final source =
          jsonDecode(await repo.createBackupJson()) as Map<String, dynamic>;
      source['version'] = 1;
      for (final row in (source['tables']['workouts'] as List)) {
        for (final field in [
          'finished_recorded_at',
          'finish_time_source',
          'finish_time_issues',
        ]) {
          row.remove(field);
        }
      }
      for (final row in (source['tables']['sets'] as List)) {
        row.remove('recorded_at');
      }
      await repo.restoreBackupJson(jsonEncode(source));
      final w = (await repo.load()).single;
      expect(w.exercises.single.sets.single.recordedAt, isNull);
      expect(w.finishedRecordedAt, isNull);
      expect(w.finishTimeSource, isNull);
    },
  );

  test(
    'overlap, before start and future are warnings; adjacent sessions are valid',
    () {
      Workout w(String id, DateTime start, DateTime? end) => Workout(
        id: id,
        name: id,
        startedAt: start,
        finishedAt: end,
        exercises: [],
      );
      final active = w('active', DateTime(2026, 10, 8, 9), null);
      final previous = w(
        'previous',
        DateTime(2026, 10, 8, 8),
        DateTime(2026, 10, 8, 9),
      );
      final next = w(
        'next',
        DateTime(2026, 10, 8, 12),
        DateTime(2026, 10, 8, 13),
      );
      final current = DateTime(2026, 10, 8, 17);
      expect(
        reviewFinishTime(
          active,
          [previous, next],
          DateTime(2026, 10, 8, 12),
          current,
        ),
        isEmpty,
      );
      expect(
        reviewFinishTime(
          active,
          [previous, next],
          DateTime(2026, 10, 8, 12, 30),
          current,
        ).map((i) => i.code),
        ['overlap:next'],
      );
      expect(
        reviewFinishTime(
          active,
          [],
          DateTime(2026, 10, 8, 8),
          current,
        ).map((i) => i.code),
        ['before_start'],
      );
      expect(
        reviewFinishTime(
          active,
          [],
          DateTime(2026, 10, 8, 18),
          current,
        ).map((i) => i.code),
        ['in_future'],
      );
    },
  );
}
