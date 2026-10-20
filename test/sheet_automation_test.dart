import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/sheet_automation.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_sync_service.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/sheet_sync.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/domain/workout.dart';
import 'sheet_sync_test.dart' show syncSnapshot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const identity = UserProfile(
    subject: 'destination',
    email: 'dest@example.test',
  );
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  late SheetAutomation automation;
  late SheetContext sheet;
  final calls = <MethodCall>[];
  final receipts = <String, String>{};
  var expired = false, revoked = false, arbitrary = false, network = false;
  var response = '';
  Future<void> Function()? beforePlanReturn;
  var pauseDuringWrite = false;
  Map<String, dynamic>? directSnapshot;
  final prompts = <String>[];
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'gymia.sheet.destination.v1': jsonEncode(identity.toJson()),
    });
    await ProfileStore.instance.load();
    calls.clear();
    receipts.clear();
    prompts.clear();
    expired = false;
    revoked = false;
    arbitrary = false;
    network = false;
    directSnapshot = null;
    dir = await Directory.systemTemp.createTemp('gymia-auto-sheets-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/qa.sqlite',
    );
    final id = await repo.start('Entreno original');
    await repo.addExercise(id, 'Press');
    await repo.addSet(
      (await repo.load()).single.exercises.single.id,
      '60',
      '10',
    );
    await repo.finish(id, acceptTimeConflicts: true);
    controller = WorkoutController(repo);
    await controller.refresh();
    sheet = SheetContext(
      id: 'file',
      name: 'Progreso',
      title: 'Resumen 2026',
      loadedAt: DateTime(2026, 10, 1),
      rows: const [canonicalHeaders],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, (call) async {
          calls.add(call);
          final args = call.arguments as Map? ?? {};
          switch (call.method) {
            case 'authorizeWrite':
              expect(args['interactive'], false);
              if (revoked) {
                throw PlatformException(
                  code: 'GOOGLE_RECONNECT_REQUIRED',
                  message: 'Permiso retirado',
                );
              }
              return true;
            case 'clearSheetToken':
              return null;
            case 'syncSnapshot':
              if (network) throw PlatformException(code: 'GOOGLE_NETWORK');
              if (expired) {
                expired = false;
                throw PlatformException(code: 'GOOGLE_AUTH_REQUIRED');
              }
              if (directSnapshot != null) return directSnapshot;
              return syncSnapshot(
                rows:
                    arbitrary
                        ? [
                          ['Fecha', 'Press', 'Carga'],
                        ]
                        : null,
                occupied: arbitrary ? ['0:0', '0:1', '0:2'] : null,
              );
            case 'syncStatus':
              return {
                'synced': receipts[args['sourceKey']] == args['sourceVersion'],
              };
            case 'writeWorkout':
              if (pauseDuringWrite) await automation.service.pauseAutomation();
              if (directSnapshot != null) {
                final writes = args['writes'] as List;
                for (final raw in writes) {
                  final cell = raw as Map;
                  final row = cell['row'] as int;
                  final column = cell['column'] as int;
                  final value = cell['value'];
                  (directSnapshot!['entered'] as Map)['$row:$column'] =
                      value is num
                          ? {'numberValue': value}
                          : value is bool
                          ? {'boolValue': value}
                          : {'stringValue': value};
                  ((directSnapshot!['rows'] as List)[row] as List)[column] =
                      value.toString();
                }
              }
              receipts[args['sourceKey'] as String] =
                  args['sourceVersion'] as String;
              return {'synced': true};
          }
          throw StateError(
            'Unexpected Google UI/API operation: ${call.method}',
          );
        });
    await const AiSettingsStore().save(
      const AiConfig(
        service: AiService.custom,
        protocol: AiProtocol.chatCompletions,
        baseUrl: 'https://example.test/v1',
        model: 'qa',
        apiKey: 'fake',
      ),
    );
    beforePlanReturn = null;
    pauseDuringWrite = false;
    response =
        '```gymia-sheet-plan\n{"summary":"Resultados en bloque de octubre","layout":"Fecha en A, carga de Press en C, repeticiones en D; cada día ocupa su fila","writes":[{"cell":"C42","value":60},{"cell":"D42","value":10}]}\n```';
    final client = AiClient(
      transport: (_, __, body) async {
        prompts.add(jsonEncode(body));
        await beforePlanReturn?.call();
        return {
          'choices': [
            {
              'message': {'content': response},
            },
          ],
        };
      },
    );
    automation = SheetAutomation(controller, client: client);
    automation.service.identity = identity;
    await automation.service.bind(
      sheet,
      syncSnapshot(),
      allowOverwrite: true,
      instructions: 'Usar bloques existentes, no añadir una tabla nueva',
    );
    await SheetContextStore().save(sheet);
  });
  tearDown(() async {
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, null);
  });

  test(
    'chat edit checks displayed old value, writes once and verifies Google readback',
    () async {
      directSnapshot =
          jsonDecode(
                jsonEncode({
                  ...syncSnapshot(
                    rows: [
                      ['Fecha', 'Ejercicio', 'Carga'],
                      ['21/10/2026', 'Press', '55'],
                    ],
                    occupied: ['0:0', '0:1', '0:2', '1:0', '1:1', '1:2'],
                  ),
                  'entered': {
                    '1:2': {'numberValue': 55},
                  },
                }),
              )
              as Map<String, dynamic>;
      const edit =
          '```gymia-sheet-edit\n{"summary":"Corregir carga","writes":[{"cell":"C2","expected":"55","value":60}]}\n```';
      final result = await automation.directEdit(edit, 'chat-1:mensaje-1');
      expect(result, contains('Google Sheets confirmó'));
      expect(result, contains('C2'));
      final writes =
          calls.where((call) => call.method == 'writeWorkout').toList();
      expect(writes, hasLength(1));
      final args = writes.single.arguments as Map;
      expect(args['sourceKey'], startsWith('local:edit/'));
      expect(((args['writes'] as List).single as Map)['expected'], {
        'numberValue': 55,
      });
      expect((directSnapshot!['entered'] as Map)['1:2'], {'numberValue': 60});
      expect(calls.where((call) => call.method == 'authorizeWrite').length, 1);
    },
  );

  test('chat edit refuses a changed cell before writing', () async {
    directSnapshot =
        jsonDecode(
              jsonEncode({
                ...syncSnapshot(
                  rows: [
                    ['Fecha', 'Ejercicio', 'Carga'],
                    ['21/10/2026', 'Press', '55'],
                  ],
                  occupied: ['1:2'],
                ),
                'entered': {
                  '1:2': {'numberValue': 55},
                },
              }),
            )
            as Map<String, dynamic>;
    const stale =
        '```gymia-sheet-edit\n{"summary":"Corregir carga","writes":[{"cell":"C2","expected":"54","value":60}]}\n```';
    await expectLater(
      automation.directEdit(stale, 'chat-1:mensaje-2'),
      throwsA(isA<ValidationException>()),
    );
    expect(calls.where((call) => call.method == 'writeWorkout'), isEmpty);
  });

  test(
    'reuse grant after restart, read fresh and send once without picker or interactive auth',
    () async {
      final before = (await SheetContextStore().load())!.loadedAt;
      final fresh = await automation.refresh();
      expect(fresh!.loadedAt.isAfter(before), true);
      final id = controller.history.single.id;
      expect(
        await automation.synchronize(id),
        contains('Google Sheets confirmado'),
      );
      final restarted = SheetAutomation(controller);
      expect(await restarted.synchronize(id), contains('recibo existente'));
      expect(calls.where((c) => c.method == 'writeWorkout'), hasLength(1));
      expect(calls.where((c) => c.method == 'connectIdentity'), isEmpty);
      expect((await restarted.jobs()).single['status'], 'sent');
      expect((await repo.load()).single.exercises.single.sets.single.reps, 10);
    },
  );
  test('expired access silently clears token and retries read once', () async {
    expired = true;
    expect(await automation.refresh(), isNotNull);
    expect(calls.where((c) => c.method == 'clearSheetToken'), hasLength(1));
    expect(calls.where((c) => c.method == 'authorizeWrite'), hasLength(2));
    expect(calls.where((c) => c.method == 'syncSnapshot'), hasLength(2));
  });
  test('revoked grant never opens consent in a background operation', () async {
    revoked = true;
    await expectLater(
      automation.synchronize(controller.history.single.id),
      throwsA(isA<PlatformException>()),
    );
    expect(
      calls.where(
        (c) => c.method == 'connectIdentity' || c.method == 'writeWorkout',
      ),
      isEmpty,
    );
    expect(await automation.service.connection(), isNotNull);
    expect((await repo.load()), hasLength(1));
  });
  test(
    'model maps existing layout, remembers it and asks genuine clarification normally',
    () async {
      arbitrary = true;
      response = '¿La carga de Press se anota como total o por lado?';
      final id = controller.history.single.id;
      await expectLater(
        automation.synchronize(id),
        throwsA(isA<SheetClarification>()),
      );
      expect((await automation.jobs()).single['status'], 'question');
      expect(calls.where((c) => c.method == 'writeWorkout'), isEmpty);
      response =
          '```gymia-sheet-plan\n{"summary":"Carga total en su bloque","layout":"Press: C42 carga total, D42 repeticiones","writes":[{"cell":"C42","value":60},{"cell":"D42","value":10}]}\n```';
      await automation.synchronize(
        id,
        guidance: 'El usuario confirma: carga total',
      );
      final write =
          calls.singleWhere((c) => c.method == 'writeWorkout').arguments as Map;
      expect((write['writes'] as List).map((c) => [c['row'], c['column']]), [
        [41, 2],
        [41, 3],
      ]);
      expect(
        (await automation.service.connection())!['layout'],
        contains('carga total'),
      );
      expect(prompts.last, contains('carga total'));
      expect(
        prompts.last,
        contains('puede incluir actividades realizadas en varias fechas'),
      );
    },
  );
  test(
    'outbox survives failures and destination changes never redirect a pending job',
    () async {
      final id = controller.history.single.id;
      network = true;
      await expectLater(
        automation.synchronize(id),
        throwsA(isA<PlatformException>()),
      );
      final restarted = SheetAutomation(controller);
      final job = (await restarted.jobs()).single;
      expect(job['id'], 'file');
      expect(job['status'], 'pending');
      expect(job['retryAfter'], isNotNull);
      final other = SheetContext(
        id: 'other-file',
        name: 'Otra',
        title: sheet.title,
        loadedAt: DateTime.now(),
        rows: const [canonicalHeaders],
      );
      await automation.service.bind(other, syncSnapshot());
      expect((await restarted.jobs()).single['id'], 'file');
      expect((await restarted.service.connection())!['id'], 'other-file');
      expect(calls.where((c) => c.method == 'writeWorkout'), isEmpty);
    },
  );
  test(
    'automatic scan captures new completions, skips older history and pause is durable',
    () async {
      await automation.enqueueCompleted();
      expect(await automation.jobs(), isEmpty);
      final id = await repo.start('Nuevo');
      await repo.addExercise(id, 'Remo');
      await repo.addSet(
        (await repo.load()).firstWhere((w) => w.id == id).exercises.single.id,
        '40',
        '12',
      );
      await repo.finish(id, acceptTimeConflicts: true);
      await controller.refresh();
      await automation.enqueueCompleted();
      expect((await automation.jobs()).single['workoutId'], id);
      await automation.service.pauseAutomation();
      await expectLater(automation.synchronize(id), throwsA(isA<Exception>()));
      expect(calls.where((c) => c.method == 'writeWorkout'), isEmpty);
      expect(
        (await SheetAutomation(controller).service.connection())!['automatic'],
        false,
      );
    },
  );
  test('pausing while the model plans cancels the remote write', () async {
    arbitrary = true;
    beforePlanReturn = () => automation.service.pauseAutomation();
    await expectLater(
      automation.synchronize(controller.history.single.id),
      throwsA(isA<ValidationException>()),
    );
    expect(calls.where((c) => c.method == 'writeWorkout'), isEmpty);
    expect((await automation.service.connection())!['automatic'], false);
  });
  test(
    'pausing an in-flight request stays paused after its receipt arrives',
    () async {
      arbitrary = true;
      pauseDuringWrite = true;
      expect(
        await automation.synchronize(controller.history.single.id),
        contains('Google Sheets confirmado'),
      );
      expect((await automation.service.connection())!['automatic'], false);
      expect((await automation.jobs()).single['status'], 'sent');
    },
  );
}
