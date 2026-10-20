import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/ui/google_sheets_import.dart';
import 'package:gymia/domain/sheet_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const channel = MethodChannel('com.gymia.app/google-sheets');
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  late List<MethodCall> calls;
  Object? Function(MethodCall)? reply;
  SheetContext? selected;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gymia-google-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.sqlite',
    );
    controller = WorkoutController(repo);
    calls = [];
    reply = null;
    selected = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (reply != null) return reply!(call);
          return switch (call.method) {
            'authorize' => true,
            'list' => {
              'files': [
                {'id': 'sheet-1', 'name': 'Hoja de ejemplo'},
              ],
              'nextPageToken': '',
            },
            'tabs' => ['Histórico', 'Notas'],
            'read' => [
              ['Fecha', 'Ejercicio', 'Peso', 'Reps'],
              ['07/10/2026', 'Remo', '40', '8'],
            ],
            _ => throw StateError('Unexpected ${call.method}'),
          };
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester, {bool forAssistant = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute<SheetContext>(
                        builder:
                            (_) => GoogleSheetsImportScreen(
                              controller: controller,
                              forAssistant: forAssistant,
                            ),
                      ),
                    ).then(
                      (value) =>
                          selected = value is SheetContext ? value : null,
                    ),
                child: const Text('Abrir Google'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Abrir Google'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'assistant loading reviews raw rows and returns only after confirmation',
    (tester) async {
      await open(tester, forAssistant: true);
      await tester.tap(find.text('Hoja de ejemplo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.text('Revisar hoja'), findsOneWidget);
      expect(selected, isNull);
      expect(await tester.runAsync(() => repo.load()), isEmpty);
      await tester.ensureVisible(find.text('Cargar y analizar'));
      await tester.tap(find.text('Cargar y analizar'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir Google'), findsOneWidget);
      expect(selected!.rows[1], ['07/10/2026', 'Remo', '40', '8']);
      expect(selected!.title, 'Histórico');
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  testWidgets(
    'cancelled assistant preview does not load context or import workouts',
    (tester) async {
      await open(tester, forAssistant: true);
      await tester.tap(find.text('Hoja de ejemplo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.text('Tus hojas de Google Sheets'), findsOneWidget);
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  testWidgets(
    'authorizes before listing, chooses tab and opens review without saving',
    (tester) async {
      await open(tester);
      expect(calls.map((c) => c.method), ['authorize', 'list']);
      await tester.tap(find.text('Hoja de ejemplo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico'));
      await tester.pumpAndSettle();
      expect(find.text('Importar hoja'), findsOneWidget);
      expect(calls.last.arguments, {'id': 'sheet-1', 'title': 'Histórico'});
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  testWidgets(
    'incomplete authorization stays open with retry without requesting files',
    (tester) async {
      reply = (_) => null;
      await open(tester);
      expect(find.text('Tus hojas de Google Sheets'), findsOneWidget);
      expect(find.text('Conectar con Google'), findsOneWidget);
      expect(
        find.textContaining('Google no completó la autorización'),
        findsOneWidget,
      );
      expect(calls.map((c) => c.method), ['authorize']);
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  testWidgets(
    'explicit account change opens profile management instead of reusing the sheet',
    (tester) async {
      await open(tester);
      expect(calls.first.arguments, isNull);
      await tester.ensureVisible(
        find.text('Cambiar cuenta o autorizar de nuevo'),
      );
      await tester.tap(find.text('Cambiar cuenta o autorizar de nuevo'));
      await tester.pumpAndSettle();
      expect(find.text('Cuenta y datos'), findsOneWidget);
      expect(calls.where((c) => c.method == 'authorize').length, 1);
    },
  );

  testWidgets('denied authorization shows retry and does not list files', (
    tester,
  ) async {
    reply =
        (_) =>
            throw PlatformException(
              code: 'GOOGLE_AUTH',
              message: 'Cuenta no habilitada.',
            );
    await open(tester);
    expect(find.text('Cuenta no habilitada.'), findsOneWidget);
    expect(find.text('Conectar con Google'), findsOneWidget);
    expect(calls.length, 1);
  });

  testWidgets('cancelled tab choice never downloads or imports rows', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Hoja de ejemplo'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['authorize', 'list', 'tabs']);
    expect(await tester.runAsync(() => repo.load()), isEmpty);
  });

  testWidgets('search and pagination preserve query and page token', (
    tester,
  ) async {
    reply =
        (call) =>
            call.method == 'authorize'
                ? true
                : {
                  'files': [
                    {
                      'id': call.arguments['pageToken'] == null ? 'a' : 'b',
                      'name': 'Hoja',
                    },
                  ],
                  'nextPageToken':
                      call.arguments['pageToken'] == null ? 'next' : '',
                };
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Pierna');
    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'query': 'Pierna'});
    await tester.tap(find.text('Cargar más hojas'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {'query': 'Pierna', 'pageToken': 'next'});
    expect(find.text('Hoja'), findsNWidgets(2));
  });
}
