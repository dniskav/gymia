import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';

import '../test/fixtures/trackia_legacy_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android migrates and reads a media row larger than CursorWindow',
    (tester) async {
      final path =
          '${await getDatabasesPath()}/trackia-large-media-test.sqlite';
      await deleteDatabase(path);
      final fixture = await TrackiaLegacyFixture.create(
        factory: databaseFactory,
        path: path,
      );
      final bytes = Uint8List(3 * 1024 * 1024);
      final attachment = jsonEncode({
        'name': 'fixture.png',
        'mime': 'image/png',
        'base64': base64Encode(bytes),
      });
      final db = await databaseFactory.openDatabase(path);
      await db.insert('activity_messages', {
        'id': 'large-media',
        'activity_id': fixture.activityId,
        'interval_id': null,
        'text': 'Adjunto sintético grande',
        'role': 'user',
        'recorded_at': 1000,
        'metrics': '{}',
        'attachment': attachment,
        'attachment_name': 'fixture.png',
        'attachment_mime': 'image/png',
      });
      await db.close();

      final repo = await SqliteWorkoutRepository.open(path: path);
      expect((await repo.loadActivities()).single.messages, hasLength(2));
      expect(
        (await repo.loadActivityMedia('large-media'))?.bytes.length,
        bytes.length,
      );
      await repo.close();

      final backup =
          jsonDecode(await File('$path.pre-trackia-v4.json').readAsString())
              as Map<String, dynamic>;
      final tables = backup['tables'] as Map<String, dynamic>;
      final messages = tables['activity_messages'] as List<dynamic>;
      expect(
        (messages.cast<Map<String, dynamic>>().firstWhere(
          (message) => message['id'] == 'large-media',
        ))['attachment'],
        attachment,
      );
      await deleteDatabase(path);
    },
  );
}
