import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/trackia_legacy_fixtures.dart';

void main() {
  sqfliteFfiInit();
  test('synthetic fixture is SQLite v4 with a readable v3 original', () async {
    final dir = await Directory.systemTemp.createTemp('trackia-fixture-');
    try {
      final fixture = await TrackiaLegacyFixture.create(
        factory: databaseFactoryFfi,
        path: '${dir.path}/legacy.sqlite',
      );
      final db = await databaseFactoryFfi.openDatabase(fixture.path);
      try {
        expect(await db.getVersion(), 4);
        expect(
          (await db.query(
            'activity_messages',
            where: 'id = ?',
            whereArgs: [fixture.messageId],
          )).single['text'],
          fixture.original,
        );
      } finally {
        await db.close();
      }
      final backup = jsonDecode(fixture.backupV3) as Map<String, dynamic>;
      expect(backup['format'], 'gymia-backup');
      expect(backup['version'], 3);
      final tables = backup['tables'] as Map<String, dynamic>;
      expect((tables['workouts'] as List).single['id'], fixture.workoutId);
      expect((tables['exercises'] as List).single['id'], fixture.exerciseId);
      expect((tables['sets'] as List).single['id'], fixture.setId);
      expect((tables['activities'] as List).single['id'], fixture.activityId);
      expect(
        (tables['activity_messages'] as List).single['text'],
        fixture.original,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
