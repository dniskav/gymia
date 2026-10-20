import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:gymia/data/sheet_sync_service.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/ui/sheet_sync.dart';
import 'sheet_sync_test.dart' show syncSnapshot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  final calls = <MethodCall>[];
  var sent = false;
  var canonical = true;
  var denied = false;
  Map<String, dynamic> snapshot() => syncSnapshot(
    rows:
        canonical
            ? null
            : [
              ['Fecha', 'Ejercicio', 'Carga'],
            ],
    occupied: canonical ? null : ['0:0', '0:1', '0:2'],
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ProfileStore.instance.load();
    calls.clear();
    sent = false;
    canonical = true;
    denied = false;
    dir = await Directory.systemTemp.createTemp('gymia-sync-ui-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/qa.sqlite',
    );
    final id = await repo.start('Fuerza');
    await repo.addExercise(id, 'Press');
    final exercise = (await repo.load()).single.exercises.single.id;
    await repo.addSet(exercise, '60', '10');
    await repo.finish(id, acceptTimeConflicts: true);
    controller = WorkoutController(repo);
    await controller.refresh();
    await const SheetContextStore().save(
      SheetContext(
        id: 'file',
        name: 'Progreso',
        title: 'Entrenamientos',
        loadedAt: DateTime.now(),
        rows: const [canonicalHeaders],
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'connectIdentity':
              return const UserProfile(
                subject: 'dest',
                email: 'dest@example.test',
              ).toJson();
            case 'authorizeWrite':
              return !denied;
            case 'list':
              return {
                'files': [
                  {'id': 'file', 'name': 'Progreso'},
                ],
                'nextPageToken': '',
              };
            case 'tabs':
              return ['Entrenamientos'];
            case 'syncStatus':
              return {'synced': sent};
            case 'syncSnapshot':
              return snapshot();
            case 'createSpreadsheet':
              return {
                'id': 'new-file',
                'name': 'Nueva hoja',
                'title': 'Entrenamientos',
              };
            case 'writeWorkout':
              sent = true;
              return {'synced': true, 'alreadySynced': false};
          }
          throw StateError('Unexpected ${call.method}');
        });
  });
  tearDown(() async {
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, null);
  });
  Future<void> mount(
    WidgetTester tester, {
    AiClient? client,
    bool create = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SheetSyncScreen(
          controller: controller,
          client: client,
          create: create,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    if (target.evaluate().isEmpty) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review does not send, confirmation sends original results once and keeps SQLite',
    (tester) async {
      await mount(tester);
      await tap(tester, 'sync-connect');
      expect(calls.any((c) => c.method == 'writeWorkout'), false);
      await tap(tester, 'sync-prepare');
      expect(calls.any((c) => c.method == 'writeWorkout'), false);
      await tap(tester, 'sync-confirm');
      final write =
          calls.singleWhere((c) => c.method == 'writeWorkout').arguments as Map;
      expect(write['expectedSubject'], 'dest');
      expect(write['sourceKey'], 'local:${controller.workouts.single.id}');
      expect(
        (write['writes'] as List).any(
          (w) => '${w['value']}'.contains('"weight_kg":60.0'),
        ),
        true,
      );
      expect(
        jsonDecode(write['sourceVersion'] as String)['id'],
        controller.workouts.single.id,
      );
      expect(find.textContaining('Recibo comprobado'), findsOneWidget);
      expect(
        (await tester.runAsync(
          repo.load,
        ))!.single.exercises.single.sets.single.reps,
        10,
      );
      expect(ProfileStore.instance.activeId, 'local');
      await tap(tester, 'sync-prepare');
      expect(calls.where((c) => c.method == 'writeWorkout'), hasLength(1));
    },
  );
  testWidgets('changed local result invalidates the preview before writing', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'sync-connect');
    await tap(tester, 'sync-prepare');
    final set = controller.workouts.single.exercises.single.sets.single;
    await tester.runAsync(() async {
      // Simulate a concurrent restore replacing a closed record.
      final db = await databaseFactoryFfi.openDatabase('${dir.path}/qa.sqlite');
      await db.update(
        'sets',
        {'weight': 6500, 'reps': 11},
        where: 'id = ?',
        whereArgs: [set.id],
      );
    });
    await tap(tester, 'sync-confirm');
    expect(find.textContaining('El entrenamiento cambió'), findsOneWidget);
    expect(calls.any((c) => c.method == 'writeWorkout'), false);
  });
  testWidgets('model can map an existing layout but cannot write before review', (
    tester,
  ) async {
    canonical = false;
    await const AiSettingsStore().save(
      const AiConfig(
        service: AiService.custom,
        protocol: AiProtocol.chatCompletions,
        baseUrl: 'https://example.test/v1',
        model: 'qa',
        apiKey: 'fake',
      ),
    );
    final client = AiClient(
      transport: (_, __, body) async {
        expect(jsonEncode(body).contains(controller.workouts.single.id), true);
        return {
          'choices': [
            {
              'message': {
                'content':
                    'Propuesta lista.\n```gymia-sheet-plan\n{"summary":"Carga en formato existente","writes":[{"cell":"C2","value":60}]}\n```',
              },
            },
          ],
        };
      },
    );
    await mount(tester, client: client);
    await tap(tester, 'sync-connect');
    await tap(tester, 'sync-prepare');
    expect(calls.any((c) => c.method == 'writeWorkout'), false);
    await tap(tester, 'sync-confirm');
    final write =
        calls.singleWhere((c) => c.method == 'writeWorkout').arguments as Map;
    expect((write['writes'] as List).single['column'], 2);
    expect((write['writes'] as List).single['row'], 1);
  });
  testWidgets(
    'new sheet is created only by its explicit button, even without workouts',
    (tester) async {
      controller.workouts = [];
      controller.activities = [];
      await mount(tester, create: true);
      await tap(tester, 'sync-connect');
      expect(calls.any((c) => c.method == 'createSpreadsheet'), false);
      await tap(tester, 'sync-create');
      expect(calls.where((c) => c.method == 'createSpreadsheet'), hasLength(1));
      expect((await const SheetContextStore().load())!.id, 'new-file');
      expect(calls.any((c) => c.method == 'writeWorkout'), false);
      expect((await tester.runAsync(repo.load)), hasLength(1));
    },
  );
  testWidgets('denied authorization cannot create or send', (tester) async {
    denied = true;
    await mount(tester);
    await tap(tester, 'sync-connect');
    expect(find.textContaining('Google no concedió'), findsOneWidget);
    expect(
      calls.any(
        (c) => c.method == 'createSpreadsheet' || c.method == 'writeWorkout',
      ),
      false,
    );
  });
}
