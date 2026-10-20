import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/data/theme_settings.dart';
import 'package:gymia/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'appearance changes live, survives reload, follows system and preserves the workout',
    (tester) async {
      const storage = FlutterSecureStorage();
      final previous = await storage.read(key: ThemeSettings.storageKey);
      final dir = await Directory.systemTemp.createTemp('gymia-theme-qa-');
      final repo = await SqliteWorkoutRepository.open(
        path: '${dir.path}/qa.sqlite',
      );
      final id = await repo.start('Sesión de prueba');
      final controller = WorkoutController(repo, profileId: 'qa-appearance');
      await controller.refresh();
      final settings = ThemeSettings.instance;
      Future<void> openAppearance() async {
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apariencia'));
        await tester.pumpAndSettle();
      }

      Future<void> select(ThemeMode mode) async {
        await tester.tap(find.byKey(ValueKey('theme-${mode.name}')));
        for (var i = 0; i < 100 && settings.mode != mode; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(settings.mode, mode);
      }

      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).last)).brightness;
      try {
        await settings.select(ThemeMode.dark);
        await tester.pumpWidget(GymApp(controller: controller));
        await tester.pumpAndSettle();
        await openAppearance();
        await select(ThemeMode.light);
        expect(brightness(), Brightness.light);
        final restarted = ThemeSettings();
        await restarted.load();
        expect(restarted.mode, ThemeMode.light);
        restarted.dispose();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('GYMIA_VISUAL_QA')) {
          // ignore: avoid_print
          print('GYMIA_THEME_LIGHT_PREVIEW');
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        await openAppearance();
        await select(ThemeMode.dark);
        expect(brightness(), Brightness.dark);
        if (const bool.fromEnvironment('GYMIA_VISUAL_QA')) {
          // ignore: avoid_print
          print('GYMIA_THEME_DARK_PREVIEW');
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await select(ThemeMode.system);
        expect(brightness(), Brightness.light);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expect(brightness(), Brightness.dark);
        expect((await repo.load()).single.id, id);
        expect(controller.active!.name, 'Sesión de prueba');
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        if (previous == null) {
          await storage.delete(key: ThemeSettings.storageKey);
        } else {
          await storage.write(key: ThemeSettings.storageKey, value: previous);
        }
        await settings.load();
        controller.dispose();
        await repo.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
