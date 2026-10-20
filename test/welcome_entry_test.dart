import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/data/welcome_settings_store.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/ui/app.dart';
import 'package:gymia/ui/welcome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('first launch offers welcome after storage loads', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final preference = WelcomeSettings.instance;
    preference.offeredThisLaunch = false;
    await preference.load();
    final dir =
        (await tester.runAsync(
          () => Directory.systemTemp.createTemp('gymia-welcome-entry-'),
        ))!;
    final repo =
        (await tester.runAsync(
          () => SqliteWorkoutRepository.open(
            factory: databaseFactoryFfi,
            path: '${dir.path}/test.sqlite',
          ),
        ))!;
    final controller = WorkoutController(repo);
    await tester.runAsync(controller.refresh);
    await tester.pumpWidget(GymApp(controller: controller));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcome-never-again')));
    await tester.tap(find.text('Omitir'));
    await tester.pump();
    expect(preference.autoShow, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(repo.close);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('active activity delays automatic welcome until resolved', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final preference = WelcomeSettings.instance;
    preference.offeredThisLaunch = false;
    await preference.load();
    final dir =
        (await tester.runAsync(
          () => Directory.systemTemp.createTemp('gymia-welcome-active-'),
        ))!;
    final repo =
        (await tester.runAsync(
          () => SqliteWorkoutRepository.open(
            factory: databaseFactoryFfi,
            path: '${dir.path}/test.sqlite',
          ),
        ))!;
    final id =
        (await tester.runAsync(
          () => repo.prepareActivity(ActivityDefinition(name: 'Lectura')),
        ))!;
    final controller = WorkoutController(repo);
    await tester.runAsync(controller.refresh);
    await tester.pumpWidget(GymApp(controller: controller));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(WelcomeScreen), findsNothing);
    await tester.runAsync(
      () => controller.run(() => repo.cancelActivityPreparation(id)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(repo.close);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
