import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/chat_archive_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/chat_message.dart';
import 'package:gymia/ui/sheet_sync.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_sync_service.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/user_profile.dart';

class _ArchiveStreamClient extends AiClient {
  final result = Completer<String>();
  void Function(String)? emit;
  @override
  Future<String> reply(
    AiConfig config,
    List<AiMessage> messages, {
    required String system,
    required String sessionId,
    void Function(String)? onText,
  }) {
    emit = onText;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  late AiAvailability availability;
  late AiClient client;
  final payloads = <Map<String, dynamic>>[];
  const archiveStore = ChatArchiveStore(profileId: 'local');
  var reply = 'Respuesta';
  setUp(() async {
    payloads.clear();
    reply = 'Respuesta';
    FlutterSecureStorage.setMockInitialValues({
      'gymia.ai.chat.v1': jsonEncode({
        'sessionId': 'archive-qa',
        'messages': [
          const AiMessage('user', 'Detalle antiguo único').forStorage(),
          const AiMessage('assistant', 'Acuerdo antiguo').forStorage(),
        ],
      }),
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
    await const AiSettingsStore().markVerified(
      (await const AiSettingsStore().load())!,
    );
    dir = await Directory.systemTemp.createTemp('gymia-archive-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/qa.sqlite',
    );
    controller = WorkoutController(repo);
    await controller.refresh();
    availability = AiAvailability(
      catalog: AiModelCatalog(
        transport:
            (_, __) async => {
              'data': [
                {'id': 'qa'},
              ],
            },
      ),
    );
    client = AiClient(
      transport: (_, __, body) async {
        payloads.add(body);
        return {
          'choices': [
            {
              'message': {'content': reply},
            },
          ],
        };
      },
    );
  });
  tearDown(() async {
    availability.dispose();
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
          client: client,
          availability: availability,
          focusMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'model archive waits while user reads history and runs when returning to the tail',
    (tester) async {
      await const FlutterSecureStorage().write(
        key: 'gymia.ai.chat.v1',
        value: jsonEncode({
          'sessionId': 'reading-archive',
          'messages': [
            for (var i = 0; i < 60; i++)
              AiMessage(
                'assistant',
                'Antiguo $i\nDetalle\nOtra línea\nNotas',
              ).forStorage(),
          ],
        }),
      );
      final streaming = _ArchiveStreamClient();
      client = streaming;
      await mount(tester);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Continúa',
      );
      await tester.tap(find.byTooltip('Enviar'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.drag(
        find.byKey(const Key('assistant-transcript')),
        const Offset(0, 500),
      );
      await tester.pump(const Duration(milliseconds: 300));
      streaming.result.complete(
        'Listo.\n```gymia-archive\n{"title":"Fase","summary":"Resumen de continuidad","reason":"Diálogo largo"}\n```',
      );
      await drain(tester);
      expect(ChatArchiveStore.index(await archiveStore.active()), isEmpty);
      expect((await archiveStore.active())!['deferredArchive'], isNotNull);
      expect(
        find.text('El asistente archivará este chat cuando vuelvas al final.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('chat-latest')));
      await drain(tester);
      expect(ChatArchiveStore.index(await archiveStore.active()), hasLength(1));
      expect((await archiveStore.active())!['messages'], isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('partial or interrupted model output cannot archive the chat', (
    tester,
  ) async {
    final streaming = _ArchiveStreamClient();
    client = streaming;
    await mount(tester);
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'Continúa',
    );
    await tester.tap(find.byTooltip('Enviar'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(streaming.emit, isNotNull);
    streaming.emit!(
      'Cerrando.\n```gymia-archive\n{"title":"Fase","summary":"Resumen","reason":"Largo"}\n```',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(ChatArchiveStore.index(await archiveStore.active()), isEmpty);
    streaming.result.completeError(StateError('stream interrupted'));
    await drain(tester);
    final state = (await archiveStore.active())!;
    expect(ChatArchiveStore.index(state), isEmpty);
    expect(state['messages'], hasLength(3));
    expect(state['pending'], 'Continúa');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual archive preserves training records and draft, survives reopening and can be consulted',
    (tester) async {
      await tester.runAsync(() async {
        await repo.prepareActivity(ActivityDefinition(name: 'Pec Fly'));
        await repo.recordActivityMessage(
          (await repo.loadActivities()).single.id,
          'Nota original de actividad',
        );
        await controller.refresh();
      });
      final activityId = controller.focus!.id;
      await mount(tester);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Borrador sin enviar',
      );
      await tester.tap(find.byKey(const Key('archive-chat')));
      await drain(tester);
      final state = (await archiveStore.active())!;
      expect(state['messages'], isEmpty);
      expect(state['archivedActivityMessageIds'], [
        controller.focus!.messages.single.id,
      ]);
      expect(
        (await tester.runAsync(repo.loadActivities))!.single.id,
        activityId,
      );
      expect(
        controller.focus!.messages.single.text,
        'Nota original de actividad',
      );
      expect(controller.focus!.intervals, isEmpty);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        'Borrador sin enviar',
      );
      expect(find.byType(ChatMessageBody), findsNothing);
      final entry = ChatArchiveStore.index(state).single;
      expect(
        (await archiveStore.read(entry['id'] as String))['messages'],
        hasLength(3),
      );
      await tester.tap(find.byTooltip('Chats archivados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry['title'] as String));
      await tester.pumpAndSettle();
      expect(find.text('Nota original de actividad'), findsOneWidget);
      await tester.tap(find.text('Consultar desde el chat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assistant-input')), findsOneWidget);
      // Close the preparation before disposing to drain the fixture draft.
      await tester.runAsync(() async {
        await repo.cancelActivityPreparation(activityId);
        await controller.refresh();
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      expect(find.byType(ChatMessageBody), findsNothing);
      expect(ChatArchiveStore.index(await archiveStore.active()), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completed model archive frees active context and model can retrieve the original',
    (tester) async {
      await mount(tester);
      reply =
          'Cerramos esta fase.\n```gymia-archive\n{"title":"Fase cerrada","summary":"Seguimos con push.","reason":"Contexto largo"}\n```';
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Continúa',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await drain(tester);
      final state = (await archiveStore.active())!;
      final id = ChatArchiveStore.index(state).single['id'] as String;
      expect(state['messages'], isEmpty);
      expect(state['carryForward'], 'Seguimos con push.');
      expect((await archiveStore.read(id))['messages'], hasLength(4));
      reply = '```gymia-recall\n{"id":"$id","start":0}\n```';
      // First request sees only the compact summary/catalog; second sees the
      // archive page and produces the final answer without reloading everything.
      client = AiClient(
        transport: (_, __, body) async {
          payloads.add(body);
          return {
            'choices': [
              {
                'message': {
                  'content':
                      payloads.length == 2
                          ? reply
                          : 'He consultado el original.',
                },
              },
            ],
          };
        },
      );
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Consulta el detalle de antes',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await drain(tester);
      expect(payloads, hasLength(3));
      expect(jsonEncode(payloads[1]), isNot(contains('Detalle antiguo único')));
      expect(jsonEncode(payloads[2]), contains('Detalle antiguo único'));
      expect((await archiveStore.active())!['messages'], hasLength(2));
      expect(find.text('He consultado el original.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'completed model proposal opens optional sheet creation without Google mutations',
    (tester) async {
      reply =
          'Vamos a preparar la hoja.\n```gymia-sync\n{"workoutId":"","create":true,"name":"Mis entrenos"}\n```';
      await mount(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Quiero crear una hoja para mis entrenamientos',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await drain(tester);
      expect(find.byType(SheetSyncScreen), findsOneWidget);
      expect(
        find.text('Crear hoja nueva'),
        findsNothing,
      ); // Google connection precedes creation controls.
      expect(find.byKey(const Key('sync-connect')), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(key: 'gymia.sheet.creation.v1'),
        null,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SheetSyncScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('partial model sync command never opens creation or sends data', (
    tester,
  ) async {
    final stream = _ArchiveStreamClient();
    client = stream;
    await mount(tester);
    await tester.enterText(
      find.byType(TextField).last,
      'Envía el entrenamiento',
    );
    await tester.tap(find.byTooltip('Enviar'));
    for (var i = 0; i < 10 && stream.emit == null; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    stream.emit!('```gymia-sync\n{"workoutId":"","create":true}\n```');
    await tester.pump();
    expect(find.byType(SheetSyncScreen), findsNothing);
    stream.result.completeError(const SocketException('interrupted'));
    await drain(tester);
    expect(find.byType(SheetSyncScreen), findsNothing);
    expect(
      await const FlutterSecureStorage().read(key: 'gymia.sheet.creation.v1'),
      null,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'chat reads latest sheet and model writes its own mapped cells without another screen',
    (tester) async {
      final id =
          (await tester.runAsync(() async {
            final id = await repo.start('Sesión para enviar');
            await repo.addExercise(id, 'Press');
            await repo.addSet(
              (await repo.load()).single.exercises.single.id,
              '60',
              '10',
            );
            await repo.finish(id, acceptTimeConflicts: true);
            await controller.refresh();
            return id;
          }))!;
      const dest = UserProfile(
        subject: 'chat-destination',
        email: 'dest@example.test',
      );
      const secure = FlutterSecureStorage();
      await secure.write(
        key: 'gymia.sheet.destination.v1',
        value: jsonEncode(dest.toJson()),
      );
      final sheet = SheetContext(
        id: 'real-shape',
        name: 'Progreso',
        title: 'Resumen 2026',
        loadedAt: DateTime(2026, 10, 1),
        rows: const [
          ['copia antigua'],
        ],
      );
      final snapshot = <String, dynamic>{
        'rows': [
          ['Fecha', 'Press', 'Carga'],
          ['último dato remoto'],
        ],
        'occupied': ['0:0', '0:1', '0:2', '1:0'],
        'entered': <String, dynamic>{},
        'merges': <dynamic>[],
        'properties': {
          'sheetId': 7,
          'gridProperties': {'rowCount': 1000, 'columnCount': 26},
        },
      };
      final service = SheetSyncService(profileId: 'local')..identity = dest;
      await service.bind(sheet, snapshot, allowOverwrite: true);
      var written = false;
      final google = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            google.add(call);
            switch (call.method) {
              case 'authorizeWrite':
                expect((call.arguments as Map)['interactive'], false);
                return true;
              case 'syncSnapshot':
                return snapshot;
              case 'syncStatus':
                return {'synced': written};
              case 'writeWorkout':
                written = true;
                return {'synced': true};
            }
            throw StateError('Unexpected ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ProfileStore.channel, null),
      );
      final bodies = <String>[];
      client = AiClient(
        transport: (_, __, body) async {
          final json = jsonEncode(body);
          bodies.add(json);
          final planning = json.contains('Eres el intérprete de la hoja');
          expect(json, contains('último dato remoto'));
          return {
            'choices': [
              {
                'message': {
                  'content':
                      planning
                          ? '```gymia-sheet-plan\n{"summary":"Carga y reps en el bloque correcto","layout":"Press: columnas C/D","writes":[{"cell":"C42","value":60},{"cell":"D42","value":10}]}\n```'
                          : 'Voy a guardar tu progreso.\n```gymia-sync\n{"workoutId":"$id"}\n```',
                },
              },
            ],
          };
        },
      );
      await mount(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Actualiza mi hoja con este entrenamiento',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await drain(tester);
      expect(find.byType(SheetSyncScreen), findsNothing);
      expect(google.where((c) => c.method == 'writeWorkout'), hasLength(1));
      final writes =
          (google.singleWhere((c) => c.method == 'writeWorkout').arguments
                  as Map)['writes']
              as List;
      expect(writes.map((c) => [c['row'], c['column']]), [
        [41, 2],
        [41, 3],
      ]);
      expect(bodies, hasLength(2));
      expect(
        jsonEncode(jsonDecode((await secure.read(key: 'gymia.ai.chat.v1'))!)),
        contains('Google Sheets confirmado'),
      );
      expect((await tester.runAsync(repo.load))!.single.id, id);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'chat corrects a specific Google cell and confirms only after readback',
    (tester) async {
      const dest = UserProfile(
        subject: 'chat-edit',
        email: 'edit@example.test',
      );
      const secure = FlutterSecureStorage();
      await secure.write(
        key: 'gymia.sheet.destination.v1',
        value: jsonEncode(dest.toJson()),
      );
      final sheet = SheetContext(
        id: 'connected-sheet',
        name: 'Progreso',
        title: 'Resumen 2026',
        loadedAt: DateTime(2026, 10, 1),
        rows: const [
          ['copia anterior'],
        ],
      );
      final snapshot = <String, dynamic>{
        'rows': [
          ['Fecha', 'Ejercicio', 'Carga'],
          ['21/10/2026', 'Press', '55'],
        ],
        'occupied': ['0:0', '0:1', '0:2', '1:0', '1:1', '1:2'],
        'entered': <String, dynamic>{
          '1:2': {'numberValue': 55},
        },
        'merges': <dynamic>[],
        'properties': {
          'sheetId': 7,
          'gridProperties': {'rowCount': 1000, 'columnCount': 26},
        },
      };
      final service = SheetSyncService(profileId: 'local')..identity = dest;
      await service.bind(sheet, snapshot, allowOverwrite: true);
      final google = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            google.add(call);
            switch (call.method) {
              case 'authorizeWrite':
                expect((call.arguments as Map)['interactive'], false);
                return true;
              case 'syncSnapshot':
                return snapshot;
              case 'writeWorkout':
                (snapshot['entered'] as Map)['1:2'] = {'numberValue': 60};
                ((snapshot['rows'] as List)[1] as List)[2] = '60';
                return {'synced': true};
            }
            throw StateError('Unexpected ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ProfileStore.channel, null),
      );
      client = AiClient(
        transport: (_, __, body) async {
        expect(jsonEncode(body), contains('55'));
          return {
            'choices': [
              {
                'message': {
                  'content':
                      'Propongo la corrección.\n```gymia-sheet-edit\n{"summary":"Cambiar carga de Press a 60","writes":[{"cell":"C2","expected":"55","value":60}]}\n```',
                },
              },
            ],
          };
        },
      );
      await mount(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Corrige mi carga de Press de 55 a 60',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await drain(tester);
      expect(google.where((c) => c.method == 'writeWorkout'), hasLength(1));
      expect(find.byType(SheetSyncScreen), findsNothing);
      expect(
        jsonEncode(jsonDecode((await secure.read(key: 'gymia.ai.chat.v1'))!)),
        contains('Google Sheets confirmó la edición'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
