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
  final tables = <String, List<Map<String, Object?>>>{};
  for (final table in SqliteWorkoutRepository._backupTables.keys) {
    tables[table] = await db.query(table);
  }
  final source = jsonEncode({
    'format': 'gymia-backup',
    'version': 3,
    'tables': tables,
  });
  if (source.length > 20 * 1024 * 1024) {
    throw const ValidationException(
      'La copia previa supera 20 MB. Exporta y guarda una copia antes de actualizar.',
    );
  }
  final target = File('$dbPath.pre-trackia-v4.json');
  if (await target.exists()) {
    if (await target.readAsString() != source) {
      throw const ValidationException(
        'Ya existe una copia previa distinta. Consérvala antes de actualizar.',
      );
    }
    return;
  }
  final pending = File('${target.path}.tmp');
  await pending.writeAsString(source, flush: true);
  await pending.rename(target.path);
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
