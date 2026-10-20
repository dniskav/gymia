part of 'sqlite_workout_repository.dart';

/// v5 only adds tables. Legacy workouts and activities keep their IDs, values,
/// foreign keys, and v3 backup representation unchanged.
Future<void> _createTrackiaV5(Database db) async {
  await db.execute('''CREATE TABLE trackia_spaces (
    id TEXT NOT NULL, profile_id TEXT NOT NULL, name TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(revision > 0),
    PRIMARY KEY(profile_id, id))''');
  await db.execute(
    '''CREATE TABLE trackia_legacy_workout_scope (
    workout_id TEXT PRIMARY KEY REFERENCES workouts(id) ON DELETE CASCADE,
    profile_id TEXT NOT NULL, space_id TEXT NOT NULL,
    FOREIGN KEY(profile_id, space_id) REFERENCES trackia_spaces(profile_id, id))''',
  );
  await db.execute(
    '''CREATE TABLE trackia_legacy_activity_scope (
    activity_id TEXT PRIMARY KEY REFERENCES activities(id) ON DELETE CASCADE,
    profile_id TEXT NOT NULL, space_id TEXT NOT NULL,
    FOREIGN KEY(profile_id, space_id) REFERENCES trackia_spaces(profile_id, id))''',
  );
}

Future<void> _backupBeforeTrackiaV5(Database db, String dbPath) async {
  if (dbPath == inMemoryDatabasePath) return;
  final preferred = File('$dbPath.pre-trackia-v4.json');
  // A failed first attempt may have left a valid backup. Keep it and create a
  // second snapshot of the current v4 database instead of blocking startup.
  final target =
      await preferred.exists()
          ? File('${preferred.path}.${DateTime.now().microsecondsSinceEpoch}')
          : preferred;
  final pending = File('${target.path}.tmp');
  final sink = pending.openWrite();
  try {
    sink.write('{"format":"gymia-backup","version":3,"tables":{');
    var firstTable = true;
    for (final table in SqliteWorkoutRepository._backupTables.keys) {
      if (!firstTable) sink.write(',');
      firstTable = false;
      sink.write('${jsonEncode(table)}:[');
      var firstRow = true;
      var lastRowId = -9223372036854775808;
      final hasMedia = table == 'activity_messages';
      final columns = SqliteWorkoutRepository._backupTables[table]!;
      final projected =
          hasMedia
              ? 'rowid AS _backup_rowid, '
                  '${columns.where((column) => column != 'attachment').map((column) => '"$column"').join(', ')}, '
                  '(attachment IS NOT NULL) AS _backup_has_attachment'
              : 'rowid AS _backup_rowid, *';
      while (true) {
        // Never put attachment into Android's CursorWindow: one image can exceed
        // its per-row capacity even when the query is limited to one row.
        final rows = await db.rawQuery(
          'SELECT $projected FROM "$table" '
          'WHERE rowid > ? ORDER BY rowid LIMIT 4',
          [lastRowId],
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          lastRowId = row['_backup_rowid'] as int;
          if (!firstRow) sink.write(',');
          firstRow = false;
          if (!hasMedia) {
            sink.write(
              jsonEncode(
                Map<String, Object?>.from(row)..remove('_backup_rowid'),
              ),
            );
          } else {
            sink.write('{');
            for (var index = 0; index < columns.length; index++) {
              final column = columns[index];
              if (index != 0) sink.write(',');
              sink.write('${jsonEncode(column)}:');
              if (column != 'attachment') {
                sink.write(jsonEncode(row[column]));
                continue;
              }
              if (row['_backup_has_attachment'] != 1) {
                sink.write('null');
                continue;
              }
              sink.write('"');
              for (var offset = 1; ; offset += 64 * 1024) {
                final fragment =
                    (await db.rawQuery(
                          'SELECT substr(attachment, ?, ?) AS fragment '
                          'FROM activity_messages WHERE rowid = ?',
                          [offset, 64 * 1024, lastRowId],
                        )).single['fragment']
                        as String;
                if (fragment.isEmpty) break;
                final encoded = jsonEncode(fragment);
                sink.write(encoded.substring(1, encoded.length - 1));
                if (fragment.runes.length < 64 * 1024) break;
              }
              sink.write('"');
            }
            sink.write('}');
          }
        }
        await sink.flush();
      }
      sink.write(']');
    }
    sink.write('}}');
    await sink.flush();
    await sink.close();
    await pending.rename(target.path);
  } catch (_) {
    await sink.close();
    if (await pending.exists()) await pending.delete();
    rethrow;
  }
}

Future<void> _ensureTrackiaDefaultSpace(Database db, String profileId) =>
    db.transaction((tx) async {
      final owners = await tx.query('trackia_spaces', columns: ['profile_id']);
      if (owners.any((row) => row['profile_id'] != profileId)) {
        throw const ValidationException(
          'La base de datos pertenece a otro perfil; no se han movido datos.',
        );
      }
      await tx.insert('trackia_spaces', {
        'id': 'gym',
        'profile_id': profileId,
        'name': 'Gimnasio',
        'revision': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _backfillTrackiaLegacyScope(tx, profileId);
    });

Future<void> _backfillTrackiaLegacyScope(
  DatabaseExecutor tx,
  String profileId,
) async {
  await tx.rawInsert(
    '''INSERT OR IGNORE INTO trackia_legacy_workout_scope
       (workout_id, profile_id, space_id)
       SELECT id, ?, 'gym' FROM workouts''',
    [profileId],
  );
  await tx.rawInsert(
    '''INSERT OR IGNORE INTO trackia_legacy_activity_scope
       (activity_id, profile_id, space_id)
       SELECT id, ?, 'gym' FROM activities''',
    [profileId],
  );
}
