import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/transfer.dart';
import 'package:gymia/ui/app.dart';
import 'package:gymia/ui/data_transfer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('review CSV, import once, backup and restore on device', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final path =
        '${await getDatabasesPath()}/gymia-transfer-integration.sqlite';
    await deleteDatabase(path);
    final repo = await SqliteWorkoutRepository.open(path: path);
    final controller = WorkoutController(repo);
    await controller.refresh();
    final sheet = CsvSheet.parse(
      'Fecha;Sesión;Ejercicio;Peso;Reps\n07/10/2026;Empuje;Press banca;60,5;8\n07/10/2026;Empuje;Press banca;62,5;6\n07/10/2026;Empuje;Remo;20;0',
    );
    await tester.pumpWidget(GymApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar / importar'));
    await tester.pumpAndSettle();
    expect(find.text('Crear y compartir copia'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: gymTheme,
        home: CsvImportScreen(controller: controller, sheet: sheet),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar importación'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 sesión nueva'), findsOneWidget);
    expect(find.textContaining('Fila 4'), findsOneWidget);
    await tester.tap(find.text('Empuje'));
    await tester.pumpAndSettle();
    expect(find.textContaining('60,5 kg × 8'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Importar sesiones nuevas'),
      240,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 20,
    );
    await tester.tap(find.text('Importar sesiones nuevas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar').last);
    await tester.pumpAndSettle();
    expect((await repo.load()).single.setCount, 2);
    final backup = await repo.createBackupJson();
    expect(repo.inspectBackupJson(backup).workouts, 1);
    expect(
      (await repo.importWorkouts(
        sheet.preview(sheet.suggestedMapping()).workouts,
      )).duplicates,
      1,
    );
    final active = await repo.start('Sesión nueva');
    expect((await repo.load()).length, 2);
    await repo.restoreBackupJson(backup);
    expect((await repo.load()).single.isActive, isFalse);
    expect((await repo.load()).single.id, isNot(active));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await repo.close();
  });
}
