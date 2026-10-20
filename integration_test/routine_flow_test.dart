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
    'create/edit/reorder routine, train, timer, previous values and delete safely',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final path =
          '${await getDatabasesPath()}/gymia-routines-integration.sqlite';
      await deleteDatabase(path);
      final repo = await SqliteWorkoutRepository.open(path: path);
      final controller = WorkoutController(repo);
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

      Future<void> reveal(Finder target) async {
        for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
          await tester.drag(
            find.byType(Scrollable).last,
            const Offset(0, -240),
          );
          await tester.pumpAndSettle();
        }
        expect(target, findsWidgets);
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
      }

      Future<void> tap(String text) async {
        final target = find.text(text);
        await reveal(target);
        await tester.tap(target.last);
        await tester.pumpAndSettle();
      }

      Future<void> exercise(String name) async {
        await tap('Añadir ejercicio a rutina');
        await tester.enterText(
          find.byKey(const Key('routine-exercise-name')),
          name,
        );
        await tap('Guardar ejercicio');
      }

      await tap('Rutinas');
      await tap('Crear rutina');
      await tester.enterText(find.byKey(const Key('routine-name')), 'Pierna A');
      await exercise('Sentadilla');
      await exercise('Remo');
      final move = find.byTooltip('Subir ejercicio 2');
      await reveal(move);
      await tester.tap(move);
      await tester.pumpAndSettle();
      await tap('Guardar rutina');
      expect(controller.routines.single.exercises.first.name, 'Remo');

      await tester.tap(find.byTooltip('Opciones de Pierna A'));
      await tester.pumpAndSettle();
      await tap('Editar rutina');
      await tester.enterText(
        find.byKey(const Key('routine-name')),
        'Mi rutina',
      );
      await tester.tap(find.byTooltip('Editar ejercicio 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('target-sets')), '2');
      await tap('Guardar ejercicio');
      await tap('Guardar rutina');
      await tap('Entrenar');
      expect(controller.active!.setCount, 0);
      expect(controller.active!.exercises.first.targetSets, 2);

      // First card is Remo. Scroll from the top until the first add-set action.
      final add = find.text('Añadir serie');
      await reveal(add);
      await tester.tap(add.first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weight-input')), '20,5');
      await tester.enterText(find.byKey(const Key('reps-input')), '10');
      await tap('Guardar');
      expect(controller.active!.setCount, 1);
      expect(controller.active!.exercises.first.sets.single.weight, 2050);

      await tap('Iniciar descanso');
      await tester.pump(const Duration(milliseconds: 700));
      await tap('Pausar');
      expect(controller.restTimer!.endsAt, isNull);
      expect(controller.restTimer!.remainingMs, lessThan(90000));
      await tap('Continuar');
      expect(controller.restTimer!.endsAt, isNotNull);
      await tester.tap(find.byTooltip('Reiniciar descanso'));
      await tester.pumpAndSettle();
      expect(
        controller.restTimer!.remainingAt(DateTime.now()),
        greaterThan(85000),
      );
      await tap('90s · Ajustar');
      await tester.enterText(find.byKey(const Key('timer-duration')), '5');
      await tap('Aplicar');
      await tap('Iniciar descanso');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Descanso terminado'), findsOneWidget);

      await tap('Finalizar entrenamiento');
      await tap('Guardar');
      expect(controller.history.single.exercises.first.targetSets, 2);
      // Let the saved confirmation dismiss before tapping the bottom action.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap('Ver historial');
      await tap('Rutinas');
      await tap('Entrenar');
      await reveal(find.text('20,5 kg × 10'));
      expect(find.text('20,5 kg × 10'), findsOneWidget);
      expect(controller.active!.setCount, 0);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones de Mi rutina'));
      await tester.pumpAndSettle();
      await tap('Eliminar rutina');
      await tap('Eliminar');
      expect(controller.routines, isEmpty);
      expect(controller.active!.exercises.length, 2);
      expect(controller.history.single.setCount, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await repo.close();
    },
  );
}
