import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gymia/application/rest_notifications.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('com.gymia.app/rest-notifications');

  testWidgets(
    'watch-style actions start the right interval and close only the notice',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Prueba de acciones'))),
      );
      await tester.runAsync(() async {
        final path = '${await getDatabasesPath()}/trackia-watch-actions.sqlite';
        await deleteDatabase(path);
        final repo = await SqliteWorkoutRepository.open(path: path);
        final controller = WorkoutController(repo);
        final notifications = RestNotificationController(controller);
        addTearDown(() async {
          notifications.dispose();
          controller.dispose();
          await repo.close();
          await deleteDatabase(path);
          await bridge.invokeMethod<void>('cancel');
        });

        final status = await bridge.invokeMapMethod<String, dynamic>('status');
        expect(status?['granted'], isTrue);
        expect(status?['exact'], isTrue);
        expect(
          await bridge.invokeMethod<bool>('enable', {'enabled': true}),
          isTrue,
        );
        await repo.prepareActivity(
          ActivityDefinition(name: 'Prueba reloj', restSeconds: 2),
        );
        await controller.refresh();
        await notifications.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          await bridge.invokeMethod<bool>('testTapStart', {'prepared': true}),
          isTrue,
        );
        await _until(() => controller.focus?.running != null);
        expect(controller.focus!.intervals.length, 1);
        expect(await bridge.invokeMethod<dynamic>('pendingAction'), isNull);

        expect(await bridge.invokeMethod<bool>('testTapStop'), isTrue);
        await _until(
          () =>
              controller.focus?.running == null &&
              controller.focus?.restEndsAt != null,
        );
        await _until(() => controller.focus?.restEndsAt != null);
        await _until(() async {
          final state = await bridge.invokeMapMethod<String, dynamic>('status');
          return state?['lastDeliveredId'] == controller.focus!.id;
        });
        expect(
          await bridge.invokeMethod<bool>('testTapStart', {'prepared': false}),
          isTrue,
        );
        await _until(
          () =>
              controller.focus?.running != null &&
              controller.focus!.intervals.length == 2,
        );
        expect(await bridge.invokeMethod<dynamic>('pendingAction'), isNull);

        expect(await bridge.invokeMethod<bool>('testTapStop'), isTrue);
        await _until(
          () =>
              controller.focus?.running == null &&
              controller.focus?.restEndsAt != null,
        );
        final secondEnd = controller.focus!.restEndsAt!.millisecondsSinceEpoch;
        await _until(() async {
          final state = await bridge.invokeMapMethod<String, dynamic>('status');
          return state?['lastDeliveredEnd'] == secondEnd;
        });
        expect(
          await bridge.invokeMethod<bool>('testTapClose', {'prepared': false}),
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await controller.refresh();
        expect(controller.focus!.running, isNull);
        expect(controller.focus!.intervals.length, 2);
        expect(await bridge.invokeMethod<dynamic>('pendingAction'), isNull);
      });
    },
  );
}

Future<void> _until(FutureOr<bool> Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('La acción de Android no llegó a tiempo.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
