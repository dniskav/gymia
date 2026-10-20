import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'complete offline workout, edit/delete, recover active and history',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final path = '${await getDatabasesPath()}/gymia-integration.sqlite';
      await deleteDatabase(path);
      var repo = await SqliteWorkoutRepository.open(path: path);
      var controller = WorkoutController(repo);
      await controller.refresh();
      // Test the retained manual workout screen; the root is now AI chat.
      await tester.pumpWidget(
        MaterialApp(
          theme: gymTheme,
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: GymHome(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tap(String text) async {
        final target = find.text(text).last;
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            250,
            scrollable: find.byType(Scrollable).last,
            maxScrolls: 30,
          );
        }
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> addSet(String kg, String reps) async {
        await tap('Añadir serie');
        await tester.enterText(find.byKey(const Key('weight-input')), kg);
        await tester.enterText(find.byKey(const Key('reps-input')), reps);
        await tap('Guardar');
      }

      await tap('Empezar entrenamiento');
      await tester.enterText(find.byType(TextFormField), 'Pierna · prueba');
      await tap('Empezar');
      await tap('Añadir ejercicio');
      await tester.enterText(find.byType(TextFormField), 'Sentadilla');
      await tap('Añadir');
      await addSet('60,5', '10');
      await addSet('65', '8');
      expect(controller.active!.setCount, 2);

      await tester.ensureVisible(find.byTooltip('Opciones de la serie 1'));
      await tester.tap(find.byTooltip('Opciones de la serie 1'));
      await tester.pumpAndSettle();
      await tap('Editar serie');
      await tester.enterText(find.byKey(const Key('weight-input')), '62,5');
      await tap('Guardar');
      expect(controller.active!.exercises.single.sets.first.weight, 6250);

      await tester.tap(find.byTooltip('Opciones de la serie 2'));
      await tester.pumpAndSettle();
      await tap('Eliminar serie');
      await tap('Eliminar');
      expect(controller.active!.setCount, 1);

      // Recreate the entire app/controller and reopen the on-disk database.
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repo.close();
      repo = await SqliteWorkoutRepository.open(path: path);
      controller = WorkoutController(repo);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: gymTheme,
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: GymHome(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tap('Continuar entrenamiento');
      expect(find.text('62,5'), findsOneWidget);
      await tap('Finalizar entrenamiento');
      await tap('Guardar');
      expect(controller.active, isNull);
      await tap('Ver historial');
      expect(find.text('Pierna · prueba'), findsOneWidget);
      await tap('Pierna · prueba');
      expect(find.text('62,5'), findsOneWidget);
      expect(find.text('COMPLETADO'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repo.close();
    },
  );
}
