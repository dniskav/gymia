import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/ui/data_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('com.gymia.app/import');
  const button = 'Elegir archivo del móvil o Drive';
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  late Directory dir;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('gymia-picker-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/db.sqlite',
    );
    controller = WorkoutController(repo);
    await controller.refresh();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DataTransferScreen(controller: controller)),
    );
    await tester.ensureVisible(find.text(button));
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
  }

  testWidgets('selected cloud data opens preview without writing sessions', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'pickSheet');
          return {
            'name': 'Hoja de ejemplo',
            'bytes': Uint8List.fromList(
              utf8.encode('Fecha;Ejercicio;Peso;Reps\n07/10/2026;Remo;40;8'),
            ),
          };
        });
    await open(tester);
    expect(find.text('Revisar hoja'), findsOneWidget);
    expect(find.textContaining('2 filas leídas'), findsOneWidget);
    await tester.ensureVisible(find.text('Cargar hoja'));
    await tester.tap(find.text('Cargar hoja'));
    await tester.pumpAndSettle();
    expect(
      (await const SheetContextStore().load())!.interpretationPending,
      isTrue,
    );
    expect(await tester.runAsync(() => repo.load()), isEmpty);
  });

  testWidgets('cancel leaves data untouched and allows another selection', (
    tester,
  ) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          return null;
        });
    await open(tester);
    expect(find.text('Tus datos'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(await tester.runAsync(() => repo.load()), isEmpty);
  });

  testWidgets('provider error is shown and does not import data', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'IMPORT_FAILED',
            message: 'Drive no pudo descargar la hoja.',
          );
        });
    await open(tester);
    expect(find.text('Drive no pudo descargar la hoja.'), findsOneWidget);
    expect(await tester.runAsync(() => repo.load()), isEmpty);
  });
}
