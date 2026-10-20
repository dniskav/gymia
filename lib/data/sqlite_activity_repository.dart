part of 'sqlite_workout_repository.dart';

Future<void> _migrateV4(Database db) async {
  await db.execute(
    '''CREATE TABLE activities (
    id TEXT PRIMARY KEY, workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id TEXT REFERENCES exercises(id) ON DELETE SET NULL,
    definition TEXT NOT NULL, created_at INTEGER NOT NULL, finished_at INTEGER, finished_recorded_at INTEGER, finish_time_issues TEXT,
    active_slot INTEGER UNIQUE DEFAULT 1, draft TEXT NOT NULL DEFAULT '', rest_ends_at INTEGER,
    CHECK ((finished_at IS NULL AND active_slot IS 1) OR (finished_at IS NOT NULL AND active_slot IS NULL)))''',
  );
  await db.execute(
    '''CREATE TABLE activity_intervals (
    id TEXT PRIMARY KEY, activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    started_at INTEGER NOT NULL, ended_at INTEGER, rest_seconds INTEGER CHECK(rest_seconds BETWEEN 0 AND 1800), running_slot INTEGER UNIQUE DEFAULT 1,
    CHECK ((ended_at IS NULL AND running_slot IS 1) OR (ended_at IS NOT NULL AND running_slot IS NULL)))''',
  );
  await db.execute(
    '''CREATE TABLE activity_messages (
    id TEXT PRIMARY KEY, activity_id TEXT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    interval_id TEXT REFERENCES activity_intervals(id) ON DELETE CASCADE,
    text TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    recorded_at INTEGER NOT NULL, metrics TEXT NOT NULL, attachment TEXT, attachment_name TEXT, attachment_mime TEXT)''',
  );
  await db.execute('CREATE INDEX activity_workout ON activities(workout_id)');
  await db.execute(
    'CREATE INDEX interval_activity ON activity_intervals(activity_id)',
  );
  await db.execute(
    'CREATE INDEX message_activity ON activity_messages(activity_id)',
  );
}

mixin _SqliteActivities implements ActivityRepository {
  @override
  Future<void> renameActivity(String activityId, String name) =>
      _db.transaction((tx) async {
        final row = await _activeActivity(tx, activityId);
        final definition = Map<String, dynamic>.from(
          jsonDecode(row['definition'] as String) as Map,
        );
        definition['name'] = validName(name);
        await tx.update(
          'activities',
          {'definition': jsonEncode(definition)},
          where: 'id = ?',
          whereArgs: [activityId],
        );
      });

  @override
  Future<void> replaceActivityPreparation(
    String activityId,
    ActivityDefinition definition, {
    String? exerciseId,
  }) => _db.transaction((tx) async {
    final row = await _activeActivity(tx, activityId);
    if ((await tx.query(
      'activity_intervals',
      where: 'activity_id = ?',
      whereArgs: [activityId],
    )).isNotEmpty) {
      throw const ValidationException(
        'Esta actividad ya empezó. Usa Parar y Terminar.',
      );
    }
    if (exerciseId != null &&
        (await tx.query(
          'exercises',
          where: 'id = ? AND workout_id = ?',
          whereArgs: [exerciseId, row['workout_id']],
        )).isEmpty) {
      throw const ValidationException(
        'El ejercicio ya no está en este entrenamiento.',
      );
    }
    final now = _now().millisecondsSinceEpoch;
    await tx.update(
      'activities',
      {
        'finished_at': now,
        'finished_recorded_at': now,
        'finish_time_issues': '["not_started"]',
        'active_slot': null,
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
    await tx.insert('activities', {
      'id': _activityUuid.v4(),
      'workout_id': row['workout_id'],
      'exercise_id': exerciseId,
      'definition': jsonEncode(definition.toJson()),
      'created_at': now,
    });
  });

  @override
  Future<void> resumeActivityPreparation(String activityId) => _db.transaction((
    tx,
  ) async {
    final rows = await tx.query(
      'activities',
      where: 'id = ?',
      whereArgs: [activityId],
    );
    if (rows.isEmpty) {
      throw const ValidationException('No se encuentra la preparación.');
    }
    final row = rows.single;
    final issues =
        jsonDecode(row['finish_time_issues'] as String? ?? '[]') as List;
    if (row['finished_at'] == null ||
        !issues.contains('not_started') ||
        (await tx.query(
          'activity_intervals',
          where: 'activity_id = ?',
          whereArgs: [activityId],
        )).isNotEmpty ||
        (await tx.query(
          'activities',
          where: 'finished_at IS NULL',
        )).isNotEmpty ||
        (await tx.query(
          'workouts',
          where: 'id = ? AND finished_at IS NULL',
          whereArgs: [row['workout_id']],
        )).isEmpty) {
      throw const ValidationException(
        'Solo puedes recuperar una preparación sin iniciar, en el día abierto y sin otra actividad activa.',
      );
    }
    await tx.update(
      'activities',
      {
        'finished_at': null,
        'finished_recorded_at': null,
        'finish_time_issues': null,
        'active_slot': 1,
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
  });

  @override
  Future<ActivityMedia?> loadActivityMedia(String messageId) async {
    final rows = await _db.rawQuery(
      'SELECT length(attachment) AS attachment_length '
      'FROM activity_messages WHERE id = ?',
      [messageId],
    );
    final length = rows.firstOrNull?['attachment_length'] as int?;
    if (length == null) return null;
    final source = StringBuffer();
    for (var offset = 1; offset <= length; offset += 64 * 1024) {
      final fragment = await _db.rawQuery(
        'SELECT substr(attachment, ?, ?) AS fragment '
        'FROM activity_messages WHERE id = ?',
        [offset, 64 * 1024, messageId],
      );
      source.write(fragment.single['fragment'] as String);
    }
    return ActivityMedia.fromJson(
      jsonDecode(source.toString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> cancelActivityPreparation(String activityId) =>
      _db.transaction((tx) async {
        await _activeActivity(tx, activityId);
        if ((await tx.query(
          'activity_intervals',
          where: 'activity_id = ?',
          whereArgs: [activityId],
        )).isNotEmpty) {
          throw const ValidationException(
            'Esta actividad ya empezó. Usa Parar y Terminar.',
          );
        }
        await tx.update(
          'activities',
          {
            'finished_at': _now().millisecondsSinceEpoch,
            'finished_recorded_at': _now().millisecondsSinceEpoch,
            'finish_time_issues': '["not_started"]',
            'active_slot': null,
          },
          where: 'id = ?',
          whereArgs: [activityId],
        );
      });
  @override
  Future<void> interpretActivityMessage(
    String messageId,
    Map<String, dynamic> metrics, {
    List<Map<String, String>> fields = const [],
  }) => _db.transaction((tx) async {
    final rows = await tx.rawQuery(
      'SELECT m.activity_id, m.metrics, a.definition FROM activity_messages m JOIN activities a ON a.id = m.activity_id WHERE m.id = ? AND m.role = ?',
      [messageId, 'user'],
    );
    if (rows.isEmpty) {
      throw const ValidationException('No se encuentra el registro original.');
    }
    final row = rows.single;
    final old = ActivityDefinition.fromJson(
      jsonDecode(row['definition'] as String) as Map<String, dynamic>,
    );
    final additions = <Map<String, String>>[];
    for (final field in fields) {
      final previous =
          old.fields.where((f) => f['key'] == field['key']).firstOrNull;
      if (previous != null) {
        if (previous['unit'] != field['unit'] ||
            previous['label'] != field['label']) {
          throw const ValidationException(
            'No se puede reinterpretar un campo existente.',
          );
        }
      } else {
        additions.add(field);
      }
    }
    final definition = ActivityDefinition.fromJson({
      ...old.toJson(),
      'fields': [...old.fields, ...additions],
    });
    final allowed = definition.fields.map((f) => f['key']).toSet();
    if (metrics.keys.any((k) => !allowed.contains(k)) ||
        metrics.values.any(
          (v) =>
              !(v is num && v.isFinite ||
                  v is bool ||
                  v is String && v.length <= 500),
        )) {
      throw const ValidationException(
        'La interpretación no coincide con los datos de esta actividad.',
      );
    }
    final deterministic =
        jsonDecode(row['metrics'] as String) as Map<String, dynamic>;
    await tx.update(
      'activity_messages',
      {
        'metrics': jsonEncode({...metrics, ...deterministic}),
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
    if (additions.isNotEmpty) {
      await tx.update(
        'activities',
        {'definition': jsonEncode(definition.toJson())},
        where: 'id = ?',
        whereArgs: [row['activity_id']],
      );
    }
  });
  Database get _db;
  DateTime Function() get _now;
  static const _activityUuid = Uuid();
  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.fromMillisecondsSinceEpoch(value as int);

  @override
  Future<List<FocusActivity>> loadActivities() => _db.transaction((tx) async {
    final activities = await tx.query(
      'activities',
      orderBy: 'created_at DESC, rowid DESC',
    );
    final intervals = await tx.query(
      'activity_intervals',
      orderBy: 'started_at ASC, rowid ASC',
    );
    final messages = await tx.query(
      'activity_messages',
      columns: [
        'id',
        'activity_id',
        'interval_id',
        'text',
        'role',
        'recorded_at',
        'metrics',
        'attachment_name',
        'attachment_mime',
      ],
      orderBy: 'recorded_at ASC, rowid ASC',
    );
    return activities
        .map(
          (a) => FocusActivity(
            id: a['id'] as String,
            workoutId: a['workout_id'] as String,
            exerciseId: a['exercise_id'] as String?,
            definition: ActivityDefinition.fromJson(
              jsonDecode(a['definition'] as String) as Map<String, dynamic>,
            ),
            createdAt: _date(a['created_at'])!,
            finishedAt: _date(a['finished_at']),
            finishedRecordedAt: _date(a['finished_recorded_at']),
            finishIssues:
                a['finish_time_issues'] == null
                    ? []
                    : (jsonDecode(a['finish_time_issues'] as String) as List)
                        .cast<String>(),
            draft: a['draft'] as String,
            restEndsAt: _date(a['rest_ends_at']),
            intervals:
                intervals
                    .where((i) => i['activity_id'] == a['id'])
                    .map(
                      (i) => ActivityInterval(
                        i['id'] as String,
                        _date(i['started_at'])!,
                        _date(i['ended_at']),
                        restSeconds: i['rest_seconds'] as int?,
                      ),
                    )
                    .toList(),
            messages:
                messages
                    .where((m) => m['activity_id'] == a['id'])
                    .map(
                      (m) => ActivityMessage(
                        id: m['id'] as String,
                        text: m['text'] as String,
                        role: m['role'] as String,
                        recordedAt: _date(m['recorded_at'])!,
                        intervalId: m['interval_id'] as String?,
                        mediaName: m['attachment_name'] as String?,
                        mediaMime: m['attachment_mime'] as String?,
                        metrics:
                            jsonDecode(m['metrics'] as String)
                                as Map<String, dynamic>,
                      ),
                    )
                    .toList(),
          ),
        )
        .toList();
  });

  Future<Map<String, Object?>> _activeActivity(
    Transaction tx,
    String id,
  ) async {
    final rows = await tx.query(
      'activities',
      where: 'id = ? AND finished_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      throw const ValidationException('Esta actividad ya terminó.');
    }
    return rows.single;
  }

  @override
  Future<String> prepareActivity(
    ActivityDefinition definition, {
    String? exerciseId,
  }) => _db.transaction((tx) async {
    if ((await tx.query(
      'activities',
      where: 'finished_at IS NULL',
    )).isNotEmpty) {
      throw const ValidationException(
        'Termina la actividad actual antes de elegir otra.',
      );
    }
    var workouts = await tx.query('workouts', where: 'finished_at IS NULL');
    String workoutId;
    if (workouts.isEmpty) {
      workoutId = _activityUuid.v4();
      await tx.insert('workouts', {
        'id': workoutId,
        'name': 'Entrenamiento',
        'started_at': _now().millisecondsSinceEpoch,
      });
    } else {
      workoutId = workouts.single['id'] as String;
    }
    if (exerciseId != null &&
        (await tx.query(
          'exercises',
          where: 'id = ? AND workout_id = ?',
          whereArgs: [exerciseId, workoutId],
        )).isEmpty) {
      throw const ValidationException(
        'El ejercicio ya no está en este entrenamiento.',
      );
    }
    final id = _activityUuid.v4();
    await tx.insert('activities', {
      'id': id,
      'workout_id': workoutId,
      'exercise_id': exerciseId,
      'definition': jsonEncode(definition.toJson()),
      'created_at': _now().millisecondsSinceEpoch,
    });
    return id;
  });

  @override
  Future<void> startInterval(String activityId) => _db.transaction((tx) async {
    final a = await _activeActivity(tx, activityId);
    if ((await tx.query(
      'activity_intervals',
      where: 'ended_at IS NULL',
    )).isNotEmpty) {
      throw const ValidationException('Ya hay una serie o tramo en marcha.');
    }
    await tx.insert('activity_intervals', {
      'id': _activityUuid.v4(),
      'activity_id': activityId,
      'started_at': _now().millisecondsSinceEpoch,
    });
    await tx.update('activities', {
      'rest_ends_at': null,
    }, where: 'rest_ends_at IS NOT NULL');
    // Cancel the old manual timer too; it cannot alert during this new interval.
    await tx.delete(
      'rest_timer',
      where: 'workout_id = ?',
      whereArgs: [a['workout_id']],
    );
  });

  @override
  Future<void> stopInterval(String activityId) => _db.transaction((tx) async {
    final a = await _activeActivity(tx, activityId);
    final running = await tx.query(
      'activity_intervals',
      where: 'activity_id = ? AND ended_at IS NULL',
      whereArgs: [activityId],
    );
    if (running.isEmpty) {
      throw const ValidationException('No hay una serie o tramo en marcha.');
    }
    final now = _now().millisecondsSinceEpoch;
    final definition = ActivityDefinition.fromJson(
      jsonDecode(a['definition'] as String) as Map<String, dynamic>,
    );
    await tx.update(
      'activity_intervals',
      {
        'ended_at': now,
        'rest_seconds': definition.restSeconds,
        'running_slot': null,
      },
      where: 'id = ?',
      whereArgs: [running.single['id']],
    );
    await tx.update(
      'activities',
      {
        'rest_ends_at':
            definition.restSeconds == 0
                ? null
                : now + definition.restSeconds * 1000,
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
  });

  @override
  Future<void> setActivityDraft(String activityId, String text) =>
      _db.transaction((tx) async {
        await _activeActivity(tx, activityId);
        if (text.length > 8000) {
          throw const ValidationException(
            'El registro supera 8000 caracteres.',
          );
        }
        await tx.update(
          'activities',
          {'draft': text},
          where: 'id = ?',
          whereArgs: [activityId],
        );
      });

  @override
  Future<String> recordActivityMessage(
    String activityId,
    String text, {
    String role = 'user',
    String? intervalId,
    ActivityMedia? media,
  }) => _db.transaction((tx) async {
    // Assistant replies may arrive after Terminar. Keep their original target,
    // never redirect a delayed reply to the newly prepared activity.
    final rows = await tx.query(
      'activities',
      where: 'id = ?',
      whereArgs: [activityId],
    );
    if (rows.isEmpty ||
        !['user', 'assistant'].contains(role) ||
        text.trim().isEmpty ||
        text.length > 8000) {
      throw const ValidationException('No se puede guardar este registro.');
    }
    final a = rows.single;
    if (intervalId != null &&
        (await tx.query(
          'activity_intervals',
          where: 'id = ? AND activity_id = ?',
          whereArgs: [intervalId, activityId],
        )).isEmpty) {
      throw const ValidationException('La serie del registro ha cambiado.');
    }
    if (intervalId == null && role == 'user') {
      final intervals = await tx.query(
        'activity_intervals',
        where: 'activity_id = ?',
        whereArgs: [activityId],
        orderBy: 'started_at DESC, rowid DESC',
        limit: 1,
      );
      intervalId = intervals.firstOrNull?['id'] as String?;
    }
    final definition = ActivityDefinition.fromJson(
      jsonDecode(a['definition'] as String) as Map<String, dynamic>,
    );
    final id = _activityUuid.v4();
    await tx.insert('activity_messages', {
      'id': id,
      'activity_id': activityId,
      'interval_id': intervalId,
      'text': text,
      'role': role,
      'recorded_at': _now().millisecondsSinceEpoch,
      'attachment': media == null ? null : jsonEncode(media.toJson()),
      'attachment_name': media?.name,
      'attachment_mime': media?.mime,
      'metrics': jsonEncode(
        role == 'user' ? compactStrengthMetrics(text, definition) : {},
      ),
    });
    if (role == 'user') {
      await tx.update(
        'activities',
        {'draft': ''},
        where: 'id = ?',
        whereArgs: [activityId],
      );
    }
    return id;
  });

  @override
  Future<void> finishActivity(
    String activityId,
    DateTime end, {
    bool acceptConflicts = false,
  }) => _db.transaction((tx) async {
    final a = await _activeActivity(tx, activityId);
    final intervals = await tx.query(
      'activity_intervals',
      where: 'activity_id = ?',
      whereArgs: [activityId],
    );
    if (intervals.any((i) => i['ended_at'] == null)) {
      throw const ValidationException(
        'Pulsa Parar antes de terminar la actividad.',
      );
    }
    if (intervals.isEmpty) {
      throw const ValidationException(
        'Inicia la actividad antes de terminarla.',
      );
    }
    final ms = end.millisecondsSinceEpoch;
    final issues = [
      if (ms < (a['created_at'] as int)) 'before_start',
      if (ms > _now().millisecondsSinceEpoch) 'in_future',
      if (intervals.any((i) => ms < (i['ended_at'] as int)))
        'before_last_interval',
    ];
    if (!acceptConflicts && issues.isNotEmpty) {
      throw const ValidationException(
        'La hora elegida no coincide con los registros. Confirma si quieres conservarla.',
      );
    }
    await tx.update(
      'activities',
      {
        'finished_at': ms,
        'finished_recorded_at': _now().millisecondsSinceEpoch,
        'finish_time_issues': issues.isEmpty ? null : jsonEncode(issues),
        'active_slot': null,
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
    // Rest continues in preparation until the next interval starts. Its plan
    // remains in the interval snapshot after the live deadline is cancelled.
  });

  @override
  Future<void> setActivityRest(String activityId, int seconds) =>
      _db.transaction((tx) async {
        final rows = await tx.query(
          'activities',
          where: 'id = ?',
          whereArgs: [activityId],
        );
        if (rows.isEmpty ||
            (rows.single['finished_at'] != null &&
                rows.single['rest_ends_at'] == null)) {
          throw const ValidationException('Este descanso ya no está activo.');
        }
        final a = rows.single;
        final old = ActivityDefinition.fromJson(
          jsonDecode(a['definition'] as String) as Map<String, dynamic>,
        );
        final definition = ActivityDefinition.fromJson({
          ...old.toJson(),
          'restSeconds': seconds,
        });
        final intervals = await tx.query(
          'activity_intervals',
          where: 'activity_id = ?',
          whereArgs: [activityId],
          orderBy: 'started_at DESC, rowid DESC',
          limit: 1,
        );
        final lastEnd = intervals.firstOrNull?['ended_at'] as int?;
        if (a['rest_ends_at'] != null && lastEnd != null) {
          await tx.update(
            'activity_intervals',
            {'rest_seconds': seconds},
            where: 'id = ?',
            whereArgs: [intervals.single['id']],
          );
        }
        await tx.update(
          'activities',
          {
            'definition': jsonEncode(definition.toJson()),
            'rest_ends_at':
                a['rest_ends_at'] != null && lastEnd != null && seconds > 0
                    ? lastEnd + seconds * 1000
                    : null,
          },
          where: 'id = ?',
          whereArgs: [activityId],
        );
      });
}
