import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import '../domain/routine.dart';
import '../domain/rest_timer.dart';
import '../domain/transfer.dart';
import '../domain/transfer_repository.dart';
import '../domain/activity.dart';
import '../domain/space.dart';
part 'sqlite_activity_repository.dart';
part 'trackia_migrations.dart';

class SqliteWorkoutRepository
    with _SqliteActivities
    implements WorkoutRepository, TransferRepository {
  SqliteWorkoutRepository._(this._db, this._now);
  @override
  final DateTime Function() _now;
  @override
  final Database _db;
  static const _uuid = Uuid();

  static Future<void> _migrateV3(Database db) async {
    // Historical records have no capture-time evidence: retain nulls.
    await db.execute('ALTER TABLE sets ADD COLUMN recorded_at INTEGER');
    await db.execute(
      'ALTER TABLE workouts ADD COLUMN finished_recorded_at INTEGER',
    );
    await db.execute(
      "ALTER TABLE workouts ADD COLUMN finish_time_source TEXT CHECK(finish_time_source IN ('system', 'user'))",
    );
    await db.execute('ALTER TABLE workouts ADD COLUMN finish_time_issues TEXT');
  }

  static Future<void> _migrateV2(Database db) async {
    // Additive migration: keep all v1 IDs, sessions and sets unchanged.
    await db.execute('ALTER TABLE workouts ADD COLUMN routine_id TEXT');
    await db.execute(
      'ALTER TABLE exercises ADD COLUMN exercise_key TEXT NOT NULL DEFAULT ""',
    );
    await db.execute('ALTER TABLE exercises ADD COLUMN target_sets INTEGER');
    await db.execute('ALTER TABLE exercises ADD COLUMN reps_min INTEGER');
    await db.execute('ALTER TABLE exercises ADD COLUMN reps_max INTEGER');
    await db.execute(
      'ALTER TABLE exercises ADD COLUMN rest_seconds INTEGER NOT NULL DEFAULT 90',
    );
    for (final row in await db.query('exercises')) {
      await db.update(
        'exercises',
        {'exercise_key': exerciseKey(row['name'] as String)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await db.execute('''CREATE TABLE routines (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE routine_exercises (
      id TEXT PRIMARY KEY, routine_id TEXT NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
      name TEXT NOT NULL, position INTEGER NOT NULL,
      target_sets INTEGER NOT NULL CHECK(target_sets BETWEEN 1 AND 30),
      reps_min INTEGER NOT NULL CHECK(reps_min BETWEEN 1 AND 999),
      reps_max INTEGER NOT NULL CHECK(reps_max BETWEEN reps_min AND 999),
      rest_seconds INTEGER NOT NULL CHECK(rest_seconds BETWEEN 5 AND 1800))''');
    await db.execute(
      'CREATE INDEX routine_exercises_parent ON routine_exercises(routine_id)',
    );
    await db.execute(
      '''CREATE TABLE rest_timer (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
      duration_seconds INTEGER NOT NULL CHECK(duration_seconds BETWEEN 5 AND 1800),
      remaining_ms INTEGER NOT NULL CHECK(remaining_ms >= 0), ends_at INTEGER)''',
    );
  }

  @override
  Future<List<Routine>> loadRoutines() => _db.transaction((tx) async {
    final rows = await tx.query(
      'routines',
      orderBy: 'created_at ASC, rowid ASC',
    );
    final exercises = await tx.query(
      'routine_exercises',
      orderBy: 'position ASC',
    );
    return rows
        .map(
          (r) => Routine(
            id: r['id'] as String,
            name: r['name'] as String,
            exercises:
                exercises
                    .where((e) => e['routine_id'] == r['id'])
                    .map(
                      (e) => RoutineExerciseDraft(
                        name: e['name'] as String,
                        targetSets: e['target_sets'] as int,
                        repsMin: e['reps_min'] as int,
                        repsMax: e['reps_max'] as int,
                        restSeconds: e['rest_seconds'] as int,
                      ),
                    )
                    .toList(),
          ),
        )
        .toList();
  });

  @override
  Future<String> saveRoutine({
    String? id,
    required String name,
    required List<RoutineExerciseDraft> exercises,
  }) async {
    final clean = validName(name);
    if (exercises.isEmpty || exercises.length > 50) {
      throw const ValidationException('Añade entre 1 y 50 ejercicios.');
    }
    for (final e in exercises) {
      e.validate();
    }
    return _db.transaction((tx) async {
      final routineId = id ?? _uuid.v4();
      if (id == null) {
        await tx.insert('routines', {
          'id': routineId,
          'name': clean,
          'created_at': _now().millisecondsSinceEpoch,
        });
      } else {
        final count = await tx.update(
          'routines',
          {'name': clean},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count == 0) {
          throw const ValidationException('No se encuentra la rutina.');
        }
        await tx.delete(
          'routine_exercises',
          where: 'routine_id = ?',
          whereArgs: [id],
        );
      }
      for (var i = 0; i < exercises.length; i++) {
        final e = exercises[i];
        await tx.insert('routine_exercises', {
          'id': _uuid.v4(),
          'routine_id': routineId,
          'name': e.name.trim(),
          'position': i,
          'target_sets': e.targetSets,
          'reps_min': e.repsMin,
          'reps_max': e.repsMax,
          'rest_seconds': e.restSeconds,
        });
      }
      return routineId;
    });
  }

  @override
  Future<void> deleteRoutine(String id) async {
    await _db.delete('routines', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<String> startRoutine(String id) => _db.transaction((tx) async {
    if ((await tx.query('workouts', where: 'finished_at IS NULL')).isNotEmpty) {
      throw const ValidationException(
        'Ya tienes una sesión en curso. Continúala primero.',
      );
    }
    final rows = await tx.query('routines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const ValidationException('No se encuentra la rutina.');
    }
    final exercises = await tx.query(
      'routine_exercises',
      where: 'routine_id = ?',
      whereArgs: [id],
      orderBy: 'position ASC',
    );
    if (exercises.isEmpty) {
      throw const ValidationException(
        'La rutina necesita al menos un ejercicio.',
      );
    }
    final workoutId = _uuid.v4();
    await tx.insert('workouts', {
      'id': workoutId,
      'name': rows.single['name'],
      'started_at': _now().millisecondsSinceEpoch,
      'routine_id': id,
    });
    for (final e in exercises) {
      await tx.insert('exercises', {
        'id': _uuid.v4(),
        'workout_id': workoutId,
        'name': e['name'],
        'exercise_key': exerciseKey(e['name'] as String),
        'position': e['position'],
        'target_sets': e['target_sets'],
        'reps_min': e['reps_min'],
        'reps_max': e['reps_max'],
        'rest_seconds': e['rest_seconds'],
      });
    }
    return workoutId;
  });

  RestTimerState _timerFrom(Map<String, Object?> row) => RestTimerState(
    workoutId: row['workout_id'] as String,
    durationSeconds: row['duration_seconds'] as int,
    remainingMs: row['remaining_ms'] as int,
    endsAt:
        row['ends_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['ends_at'] as int),
  );

  @override
  Future<RestTimerState?> loadRestTimer() async {
    final rows = await _db.query('rest_timer');
    return rows.isEmpty ? null : _timerFrom(rows.single);
  }

  Future<void> _setRest(String workoutId, int seconds, bool running) async {
    parseRestSeconds('$seconds');
    await _db.transaction((tx) async {
      await _requireActive(tx, workoutId);
      await tx.insert('rest_timer', {
        'id': 1,
        'workout_id': workoutId,
        'duration_seconds': seconds,
        'remaining_ms': seconds * 1000,
        'ends_at':
            running ? _now().millisecondsSinceEpoch + seconds * 1000 : null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> startRest(String workoutId, int seconds) =>
      _setRest(workoutId, seconds, true);
  @override
  Future<void> resetRest(String workoutId, int seconds) =>
      _setRest(workoutId, seconds, false);

  @override
  Future<void> pauseRest(String workoutId) => _db.transaction((tx) async {
    await _requireActive(tx, workoutId);
    final rows = await tx.query(
      'rest_timer',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
    );
    if (rows.isEmpty) return;
    final timer = _timerFrom(rows.single);
    await tx.update('rest_timer', {
      'remaining_ms': timer.remainingAt(_now()),
      'ends_at': null,
    }, where: 'id = 1');
  });

  @override
  Future<void> resumeRest(String workoutId) => _db.transaction((tx) async {
    await _requireActive(tx, workoutId);
    final rows = await tx.query(
      'rest_timer',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
    );
    if (rows.isEmpty) return;
    final timer = _timerFrom(rows.single);
    if (timer.endsAt != null || timer.remainingMs == 0) return;
    await tx.update('rest_timer', {
      'ends_at': _now().millisecondsSinceEpoch + timer.remainingMs,
    }, where: 'id = 1');
  });

  static Future<SqliteWorkoutRepository> open({
    DatabaseFactory? factory,
    String? path,
    DateTime Function()? clock,
    String profileId = 'local',
  }) async {
    validTrackiaId(profileId);
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'gymia.sqlite');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE workouts (
          id TEXT PRIMARY KEY, name TEXT NOT NULL,
          started_at INTEGER NOT NULL, finished_at INTEGER,
          active_slot INTEGER UNIQUE DEFAULT 1,
          CHECK ((finished_at IS NULL AND active_slot IS 1)
            OR (finished_at IS NOT NULL AND active_slot IS NULL)))''');
          await db.execute('''CREATE TABLE exercises (
          id TEXT PRIMARY KEY, workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
          name TEXT NOT NULL, position INTEGER NOT NULL)''');
          await db.execute(
            'CREATE INDEX exercises_workout ON exercises(workout_id)',
          );
          await db.execute(
            '''CREATE TABLE sets (
          id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
          weight INTEGER NOT NULL CHECK(weight BETWEEN 0 AND 999999),
          reps INTEGER NOT NULL CHECK(reps BETWEEN 1 AND 999), position INTEGER NOT NULL)''',
          );
          await db.execute('CREATE INDEX sets_exercise ON sets(exercise_id)');
          await _migrateV2(db);
          await _migrateV3(db);
          await _migrateV4(db);
          await _createTrackiaV5(db);
        },
        onUpgrade: (db, old, next) async {
          if (old < 2) await _migrateV2(db);
          if (old < 3) await _migrateV3(db);
          if (old < 4) await _migrateV4(db);
          if (old < 5) {
            await _backupBeforeTrackiaV5(db, dbPath);
            await _createTrackiaV5(db);
          }
        },
      ),
    );
    try {
      await _ensureTrackiaDefaultSpace(db, profileId);
    } catch (_) {
      await db.close();
      rethrow;
    }
    return SqliteWorkoutRepository._(db, clock ?? DateTime.now);
  }

  @override
  Future<List<Workout>> load() => _db.transaction(_loadFrom);

  Future<List<Workout>> _loadFrom(DatabaseExecutor tx) async {
    final workouts = await tx.query(
      'workouts',
      orderBy: 'started_at DESC, rowid DESC',
    );
    final exercises = await tx.query('exercises', orderBy: 'position ASC');
    final sets = await tx.query('sets', orderBy: 'position ASC');
    return workouts
        .map(
          (w) => Workout(
            id: w['id'] as String,
            name: w['name'] as String,
            startedAt: DateTime.fromMillisecondsSinceEpoch(
              w['started_at'] as int,
            ),
            finishedAt:
                w['finished_at'] == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                      w['finished_at'] as int,
                    ),
            finishedRecordedAt:
                w['finished_recorded_at'] == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                      w['finished_recorded_at'] as int,
                    ),
            finishTimeSource:
                w['finish_time_source'] == null
                    ? null
                    : FinishTimeSource.values.byName(
                      w['finish_time_source'] as String,
                    ),
            finishTimeIssues:
                w['finish_time_issues'] == null
                    ? const []
                    : List<String>.unmodifiable(
                      (jsonDecode(w['finish_time_issues'] as String) as List)
                          .cast<String>(),
                    ),
            exercises:
                exercises
                    .where((e) => e['workout_id'] == w['id'])
                    .map(
                      (e) => Exercise(
                        id: e['id'] as String,
                        name: e['name'] as String,
                        targetSets: e['target_sets'] as int?,
                        repsMin: e['reps_min'] as int?,
                        repsMax: e['reps_max'] as int?,
                        restSeconds: e['rest_seconds'] as int,
                        sets:
                            sets
                                .where((s) => s['exercise_id'] == e['id'])
                                .map(
                                  (s) => WorkoutSet(
                                    id: s['id'] as String,
                                    weight: s['weight'] as int,
                                    reps: s['reps'] as int,
                                    recordedAt:
                                        s['recorded_at'] == null
                                            ? null
                                            : DateTime.fromMillisecondsSinceEpoch(
                                              s['recorded_at'] as int,
                                            ),
                                  ),
                                )
                                .toList(),
                      ),
                    )
                    .toList(),
          ),
        )
        .toList();
  }

  Future<void> _requireActive(Transaction tx, String workoutId) async {
    final rows = await tx.query(
      'workouts',
      where: 'id = ? AND finished_at IS NULL',
      whereArgs: [workoutId],
    );
    if (rows.isEmpty) {
      throw const ValidationException('Esta sesión ya no está activa.');
    }
  }

  Future<void> _requireExercise(Transaction tx, String exerciseId) async {
    final rows = await tx.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
    if (rows.isEmpty) {
      throw const ValidationException('No se encuentra el ejercicio.');
    }
    await _requireActive(tx, rows.first['workout_id'] as String);
  }

  Future<void> _requireSet(Transaction tx, String setId) async {
    final rows = await tx.query('sets', where: 'id = ?', whereArgs: [setId]);
    if (rows.isEmpty) {
      throw const ValidationException('No se encuentra la serie.');
    }
    await _requireExercise(tx, rows.first['exercise_id'] as String);
  }

  Future<int> _nextPosition(
    Transaction tx,
    String table,
    String parent,
    String id,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next FROM $table WHERE $parent = ?',
      [id],
    );
    return rows.first['next'] as int;
  }

  @override
  Future<String> start(String name) async {
    final clean = validName(name);
    return _db.transaction((tx) async {
      final active = await tx.query('workouts', where: 'finished_at IS NULL');
      if (active.isNotEmpty) {
        throw const ValidationException(
          'Ya tienes una sesión en curso. Continúala primero.',
        );
      }
      final id = _uuid.v4();
      await tx.insert('workouts', {
        'id': id,
        'name': clean,
        'started_at': _now().millisecondsSinceEpoch,
      });
      return id;
    });
  }

  @override
  Future<void> addExercise(String workoutId, String name) async {
    final clean = validName(name);
    await _db.transaction((tx) async {
      await _requireActive(tx, workoutId);
      await tx.insert('exercises', {
        'id': _uuid.v4(),
        'workout_id': workoutId,
        'name': clean,
        'exercise_key': exerciseKey(clean),
        'position': await _nextPosition(
          tx,
          'exercises',
          'workout_id',
          workoutId,
        ),
      });
    });
  }

  @override
  Future<void> addSet(String exerciseId, String weight, String reps) async {
    final w = parseWeight(weight);
    final r = parseReps(reps);
    await _db.transaction((tx) async {
      await _requireExercise(tx, exerciseId);
      await tx.insert('sets', {
        'id': _uuid.v4(),
        'exercise_id': exerciseId,
        'weight': w,
        'reps': r,
        'recorded_at': _now().millisecondsSinceEpoch,
        'position': await _nextPosition(tx, 'sets', 'exercise_id', exerciseId),
      });
    });
  }

  @override
  Future<void> editSet(String setId, String weight, String reps) async {
    final w = parseWeight(weight);
    final r = parseReps(reps);
    await _db.transaction((tx) async {
      await _requireSet(tx, setId);
      await tx.update(
        'sets',
        {'weight': w, 'reps': r},
        where: 'id = ?',
        whereArgs: [setId],
      );
    });
  }

  @override
  Future<void> deleteSet(String setId) => _db.transaction((tx) async {
    await _requireSet(tx, setId);
    await tx.delete('sets', where: 'id = ?', whereArgs: [setId]);
  });

  @override
  Future<void> deleteExercise(String exerciseId) => _db.transaction((tx) async {
    await _requireExercise(tx, exerciseId);
    await tx.delete('exercises', where: 'id = ?', whereArgs: [exerciseId]);
  });

  @override
  Future<void> finish(
    String workoutId, {
    DateTime? finishedAt,
    FinishTimeSource finishTimeSource = FinishTimeSource.user,
    bool acceptTimeConflicts = false,
  }) => _db.transaction((tx) async {
    await _requireActive(tx, workoutId);
    if ((await tx.query(
      'activities',
      where: 'workout_id = ? AND finished_at IS NULL',
      whereArgs: [workoutId],
    )).isNotEmpty) {
      throw const ValidationException(
        'Termina la actividad actual antes de finalizar el entrenamiento.',
      );
    }
    final count = Sqflite.firstIntValue(
      await tx.rawQuery(
        'SELECT COUNT(*) FROM sets s JOIN exercises e ON e.id = s.exercise_id WHERE e.workout_id = ?',
        [workoutId],
      ),
    );
    final activityCount = Sqflite.firstIntValue(
      await tx.rawQuery(
        'SELECT COUNT(*) FROM activity_intervals i JOIN activities a ON a.id = i.activity_id WHERE a.workout_id = ? AND i.ended_at IS NOT NULL',
        [workoutId],
      ),
    );
    if (count == 0 && activityCount == 0) {
      throw const ValidationException(
        'Registra al menos una serie antes de finalizar.',
      );
    }
    final recorded = _now();
    final end = finishedAt ?? recorded;
    final workouts = await _loadFrom(tx);
    final current = workouts.singleWhere((w) => w.id == workoutId);
    final ends = await tx.rawQuery(
      'SELECT i.ended_at FROM activity_intervals i JOIN activities a ON a.id = i.activity_id WHERE a.workout_id = ? AND i.ended_at IS NOT NULL',
      [workoutId],
    );
    final issues = reviewFinishTime(
      current,
      workouts,
      end,
      recorded,
      activityEnds: ends.map(
        (r) => DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int),
      ),
    );
    if (issues.isNotEmpty && !acceptTimeConflicts) {
      throw ValidationException(
        '${issues.map((i) => i.message).join('\n')} Confirma si quieres conservar esa hora.',
      );
    }
    await tx.delete(
      'rest_timer',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
    );
    await tx.update(
      'activities',
      {'rest_ends_at': null},
      where: 'workout_id = ?',
      whereArgs: [workoutId],
    );
    await tx.update(
      'workouts',
      {
        'finished_at': end.millisecondsSinceEpoch,
        'finished_recorded_at': recorded.millisecondsSinceEpoch,
        'finish_time_source':
            (finishedAt == null ? FinishTimeSource.system : finishTimeSource)
                .name,
        'finish_time_issues':
            issues.isEmpty
                ? null
                : jsonEncode(issues.map((i) => i.code).toList()),
        'active_slot': null,
      },
      where: 'id = ?',
      whereArgs: [workoutId],
    );
  });

  @override
  Future<void> discard(String workoutId) => _db.transaction((tx) async {
    await _requireActive(tx, workoutId);
    await tx.delete('workouts', where: 'id = ?', whereArgs: [workoutId]);
  });

  static const _backupTables = <String, List<String>>{
    'workouts': [
      'id',
      'name',
      'started_at',
      'finished_at',
      'active_slot',
      'routine_id',
      'finished_recorded_at',
      'finish_time_source',
      'finish_time_issues',
    ],
    'exercises': [
      'id',
      'workout_id',
      'name',
      'position',
      'exercise_key',
      'target_sets',
      'reps_min',
      'reps_max',
      'rest_seconds',
    ],
    'sets': ['id', 'exercise_id', 'weight', 'reps', 'position', 'recorded_at'],
    'routines': ['id', 'name', 'created_at'],
    'routine_exercises': [
      'id',
      'routine_id',
      'name',
      'position',
      'target_sets',
      'reps_min',
      'reps_max',
      'rest_seconds',
    ],
    'rest_timer': [
      'id',
      'workout_id',
      'duration_seconds',
      'remaining_ms',
      'ends_at',
    ],
    'activities': [
      'id',
      'workout_id',
      'exercise_id',
      'definition',
      'created_at',
      'finished_at',
      'active_slot',
      'draft',
      'rest_ends_at',
      'finished_recorded_at',
      'finish_time_issues',
    ],
    'activity_intervals': [
      'id',
      'activity_id',
      'started_at',
      'ended_at',
      'rest_seconds',
      'running_slot',
    ],
    'activity_messages': [
      'id',
      'activity_id',
      'interval_id',
      'text',
      'role',
      'recorded_at',
      'metrics',
      'attachment',
      'attachment_name',
      'attachment_mime',
    ],
  };
  static const _backupIntFields = <String>{
    'started_at',
    'finished_at',
    'active_slot',
    'position',
    'target_sets',
    'reps_min',
    'reps_max',
    'rest_seconds',
    'weight',
    'reps',
    'created_at',
    'duration_seconds',
    'remaining_ms',
    'ends_at',
    'recorded_at',
    'finished_recorded_at',
    'rest_ends_at',
    'ended_at',
    'running_slot',
  };
  static const _backupNullable = <String>{
    'finished_at',
    'active_slot',
    'routine_id',
    'target_sets',
    'reps_min',
    'reps_max',
    'ends_at',
    'recorded_at',
    'finished_recorded_at',
    'finish_time_source',
    'finish_time_issues',
    'exercise_id',
    'rest_ends_at',
    'ended_at',
    'running_slot',
    'interval_id',
    'attachment',
    'attachment_name',
    'attachment_mime',
  };

  @override
  Future<String> createBackupJson() => _db.transaction((tx) async {
    final attachmentSize =
        Sqflite.firstIntValue(
          await tx.rawQuery(
            'SELECT COALESCE(SUM(length(attachment)), 0) FROM activity_messages',
          ),
        ) ??
        0;
    if (attachmentSize > 20 * 1024 * 1024) {
      throw const ValidationException(
        'Los adjuntos superan el límite de 20 MB de la copia. Los registros siguen guardados en el móvil.',
      );
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _backupTables.keys) {
      tables[table] = await tx.query(table);
    }
    final source = jsonEncode({
      'format': 'gymia-backup',
      'version': 3,
      'tables': tables,
    });
    if (source.length > 20 * 1024 * 1024) {
      throw const ValidationException(
        'La copia completa supera 20 MB. No se ha exportado una copia parcial.',
      );
    }
    return source;
  });

  Map<String, List<Map<String, Object?>>> _parseBackup(String source) {
    if (source.length > 20 * 1024 * 1024) {
      throw const ValidationException('La copia supera 20 MB.');
    }
    try {
      final root = jsonDecode(source);
      if (root is! Map ||
          root['format'] != 'gymia-backup' ||
          ![1, 2, 3].contains(root['version']) ||
          root['tables'] is! Map) {
        throw const FormatException();
      }
      final rawTables = root['tables'] as Map;
      final result = <String, List<Map<String, Object?>>>{};
      for (final entry in _backupTables.entries) {
        if ((root['version'] as int) < 3 &&
            [
              'activities',
              'activity_intervals',
              'activity_messages',
            ].contains(entry.key)) {
          result[entry.key] = [];
          continue;
        }
        final raw = rawTables[entry.key];
        if (raw is! List) throw const FormatException();
        result[entry.key] =
            raw.map((item) {
              // Version 1 backups predate timestamp provenance. Do not invent it.
              if (root['version'] == 1 && item is Map) {
                item = Map<String, dynamic>.from(item);
                for (final column in [
                  'recorded_at',
                  'finished_recorded_at',
                  'finish_time_source',
                  'finish_time_issues',
                ]) {
                  if (entry.value.contains(column)) item[column] = null;
                }
              }
              if (item is! Map ||
                  item.keys
                      .toSet()
                      .difference(entry.value.toSet())
                      .isNotEmpty ||
                  !entry.value.every(item.containsKey)) {
                throw const FormatException();
              }
              final row = Map<String, Object?>.from(item);
              for (final column in entry.value) {
                final value = row[column];
                if (value == null &&
                    !_backupNullable.contains(column) &&
                    !(entry.key == 'activity_intervals' &&
                        column == 'rest_seconds')) {
                  throw const FormatException();
                }
                final isInt =
                    _backupIntFields.contains(column) ||
                    (entry.key == 'rest_timer' && column == 'id');
                if (value != null &&
                    (isInt ? value is! int : value is! String)) {
                  throw const FormatException();
                }
                if (value is String &&
                    value.length >
                        (column == 'attachment'
                            ? 6 * 1024 * 1024
                            : [
                              'finish_time_issues',
                              'definition',
                              'metrics',
                            ].contains(column)
                            ? 50000
                            : ['text', 'draft'].contains(column)
                            ? 8000
                            : 500)) {
                  throw const FormatException();
                }
                if (value is String &&
                    value.isEmpty &&
                    !['exercise_key', 'draft'].contains(column)) {
                  throw const FormatException();
                }
                if (column == 'name' && value is String) validName(value);
                if (column == 'finish_time_source' &&
                    value != null &&
                    !['system', 'user'].contains(value)) {
                  throw const FormatException();
                }
                if (column == 'finish_time_issues' && value != null) {
                  final flags = jsonDecode(value as String);
                  if (flags is! List || flags.any((f) => f is! String)) {
                    throw const FormatException();
                  }
                }
                if (column == 'definition') {
                  ActivityDefinition.fromJson(
                    jsonDecode(value as String) as Map<String, dynamic>,
                  );
                }
                if (column == 'attachment' && value != null) {
                  ActivityMedia.fromJson(
                    jsonDecode(value as String) as Map<String, dynamic>,
                  );
                }
                if (column == 'metrics' &&
                    jsonDecode(value as String) is! Map) {
                  throw const FormatException();
                }
                if (column == 'metrics') {
                  final metrics = jsonDecode(value as String) as Map;
                  if (metrics.values.any(
                    (v) =>
                        !(v is num && v.isFinite ||
                            v is bool ||
                            v is String && v.length <= 500),
                  )) {
                    throw const FormatException();
                  }
                }
              }
              return row;
            }).toList();
      }
      return result;
    } catch (_) {
      throw const ValidationException(
        'La copia no es un archivo GymIA válido (formato 1, 2 o 3).',
      );
    }
  }

  @override
  BackupSummary inspectBackupJson(String source) {
    final tables = _parseBackup(source);
    return BackupSummary(
      tables['workouts']!.length,
      tables['routines']!.length,
      tables['workouts']!.any((w) => w['finished_at'] == null),
    );
  }

  @override
  Future<void> restoreBackupJson(String source) async {
    final tables = _parseBackup(source);
    await _db.transaction((tx) async {
      await tx.delete('workouts');
      await tx.delete('routines');
      for (final table in _backupTables.keys) {
        for (final row in tables[table]!) {
          await tx.insert(table, row);
        }
      }
      final invalid = await tx.rawQuery(
        '''SELECT m.id FROM activity_messages m JOIN activity_intervals i ON i.id = m.interval_id WHERE m.activity_id != i.activity_id
        UNION ALL SELECT a.id FROM activities a JOIN workouts w ON w.id = a.workout_id WHERE a.finished_at IS NULL AND w.finished_at IS NOT NULL
        UNION ALL SELECT i.id FROM activity_intervals i JOIN activities a ON a.id = i.activity_id WHERE i.ended_at IS NULL AND a.finished_at IS NOT NULL''',
      );
      if (invalid.isNotEmpty) {
        throw const ValidationException(
          'La copia contiene actividades con relaciones incoherentes.',
        );
      }
      final owner =
          (await tx.query(
                'trackia_spaces',
                columns: ['profile_id'],
                limit: 1,
              )).single['profile_id']
              as String;
      await _backfillTrackiaLegacyScope(tx, owner);
    });
  }

  @override
  Future<Set<String>> existingFingerprints() async => {
    for (final workout in await load())
      if (!workout.isActive) workoutFingerprint(workout),
  };

  @override
  Future<ImportSummary> importWorkouts(List<ImportedWorkout> workouts) async {
    final seen = await existingFingerprints();
    var added = 0;
    var duplicates = 0;
    await _db.transaction((tx) async {
      for (final w in workouts) {
        final fingerprint = importedFingerprint(w);
        if (!seen.add(fingerprint)) {
          duplicates++;
          continue;
        }
        final name = validName(w.name);
        if (w.exercises.isEmpty || w.setCount == 0) {
          throw const ValidationException('Hay una sesión sin series.');
        }
        final workoutId = _uuid.v4();
        await tx.insert('workouts', {
          'id': workoutId,
          'name': name,
          'started_at': w.date.millisecondsSinceEpoch,
          'finished_at':
              w.date.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          'active_slot': null,
        });
        for (var i = 0; i < w.exercises.length; i++) {
          final e = w.exercises[i];
          final exerciseId = _uuid.v4();
          await tx.insert('exercises', {
            'id': exerciseId,
            'workout_id': workoutId,
            'name': validName(e.name),
            'exercise_key': exerciseKey(e.name),
            'position': i,
          });
          for (var j = 0; j < e.sets.length; j++) {
            final s = e.sets[j];
            if (s.weight < 0 ||
                s.weight > 999999 ||
                s.reps < 1 ||
                s.reps > 999) {
              throw const ValidationException(
                'Hay una serie con peso o repeticiones inválidos.',
              );
            }
            await tx.insert('sets', {
              'id': _uuid.v4(),
              'exercise_id': exerciseId,
              'weight': s.weight,
              'reps': s.reps,
              'position': j,
            });
          }
        }
        added++;
      }
    });
    return ImportSummary(added, duplicates);
  }

  @override
  Future<void> close() => _db.close();
}
