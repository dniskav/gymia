import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/application/rest_notifications.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'one durable rest alarm updates with adjustment and cancels on early restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('gymia-notification-');
      var now = DateTime(2026, 10, 8, 10);
      final repo = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/db.sqlite',
        clock: () => now,
      );
      final c = WorkoutController(repo, clock: () => now);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RestNotificationController.channel, (
            call,
          ) async {
            calls.add(call);
            return call.method == 'status'
                ? {'enabled': true, 'granted': true, 'exact': true}
                : null;
          });
      final notifier = RestNotificationController(c);
      addTearDown(() async {
        notifier.dispose();
        c.dispose();
        await repo.close();
        await dir.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(RestNotificationController.channel, null);
      });
      await repo.prepareActivity(
        ActivityDefinition(name: 'Press', restSeconds: 120),
      );
      await c.refresh();
      await notifier.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await c.run(() => repo.startInterval(c.focus!.id));
      now = now.add(const Duration(seconds: 30));
      await c.run(() => repo.stopInterval(c.focus!.id));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.last.method, 'schedule');
      expect(
        calls.last.arguments['end'],
        now.add(const Duration(seconds: 120)).millisecondsSinceEpoch,
      );
      final scheduled = calls.where((v) => v.method == 'schedule').length;
      await c.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.where((v) => v.method == 'schedule').length, scheduled);
      await c.run(() => repo.setActivityRest(c.focus!.id, 90));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        calls.last.arguments['end'],
        now.add(const Duration(seconds: 90)).millisecondsSinceEpoch,
      );
      now = now.add(const Duration(seconds: 20));
      await c.run(() => repo.startInterval(c.focus!.id));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls.last.method, 'cancel');
    },
  );
}
