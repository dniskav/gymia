import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('gymia-ai-chat-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.sqlite',
    );
    controller = WorkoutController(repo);
    await controller.refresh();
  });
  tearDown(() async {
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
  const config = AiConfig(
    service: AiService.opencodeGo,
    baseUrl: 'https://opencode.ai/zen/go/v1',
    model: 'test-model',
    protocol: AiProtocol.chatCompletions,
    apiKey: 'test-secret',
  );

  testWidgets(
    'outgoing message survives interrupted screen and retry does not duplicate it',
    (tester) async {
      await const AiSettingsStore().save(config);
      await const AiSettingsStore().markVerified(config);
      final answer = Completer<Map<String, dynamic>>();
      var called = false;
      Widget app(AiClient client) => MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
          client: client,
          focusMode: true,
          availability: AiAvailability(
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'test-model'},
                    ],
                  },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        app(
          AiClient(
            transport: (_, __, ___) async {
              called = true;
              return answer.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Conserva este mensaje',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(called, isTrue);
      final saved =
          jsonDecode(
                (await const FlutterSecureStorage().read(
                  key: 'gymia.ai.chat.v1',
                ))!,
              )
              as Map;
      expect(saved['pending'], 'Conserva este mensaje');
      expect(saved['messages'], hasLength(1));
      await tester.pumpWidget(const SizedBox());
      answer.complete({
        'choices': [
          {
            'message': {'content': 'Respuesta tardía'},
          },
        ],
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app(
          AiClient(
            transport:
                (_, __, ___) async => {
                  'choices': [
                    {
                      'message': {'content': 'Recibido'},
                    },
                  ],
                },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        'Conserva este mensaje',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      final completed =
          jsonDecode(
                (await const FlutterSecureStorage().read(
                  key: 'gymia.ai.chat.v1',
                ))!,
              )
              as Map;
      expect(completed['pending'], isNull);
      expect(completed['messages'], hasLength(2));
      expect(completed['messages'].first['content'], 'Conserva este mensaje');
      expect(completed['messages'].last['content'], 'Recibido');
    },
  );

  testWidgets(
    'Google tab reaches assistant intact and survives reopening; failed refresh retains it',
    (tester) async {
      const profile = UserProfile(
        subject: 'google-test-1',
        email: 'test@example.test',
      );
      controller.dispose();
      controller = WorkoutController(repo, profileId: profile.id);
      await tester.runAsync(() => controller.refresh());
      final aiStore = AiSettingsStore(profileId: profile.id);
      final sheetStore = SheetContextStore(profileId: profile.id);
      await tester.runAsync(() => aiStore.save(config));
      await tester.runAsync(() => aiStore.markVerified(config));
      const channel = MethodChannel('com.gymia.app/google-sheets');
      var failRefresh = false;
      const rows = [
        ['Fecha', 'Sesión', 'Ejercicio', 'Serie1', 'Serie2', 'Notas'],
        [
          '28/09/2026',
          'Pull',
          'Remo unilateral',
          '25×8F/lado',
          '',
          '9 + 1 parcial; reps desconocidas',
        ],
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => switch (call.method) {
              'connectIdentity' => profile.toJson(),
              'authorize' => true,
              'list' => {
                'files': [
                  {'id': 'sheet-1', 'name': 'Hoja de entrenamiento de ejemplo'},
                ],
              },
              'tabs' => ['Registro2026'],
              'read' =>
                failRefresh
                    ? throw PlatformException(
                      code: 'GOOGLE_NETWORK',
                      message: 'Sin conexión con Google.',
                    )
                    : rows,
              _ => throw StateError('Unexpected ${call.method}'),
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await const FlutterSecureStorage().write(
        key: ProfileStore.registryKey,
        value: jsonEncode({
          'active': profile.id,
          'profiles': [profile.toJson()],
        }),
      );
      await ProfileStore.instance.load();
      final payloads = <Map<String, dynamic>>[];
      final client = AiClient(
        transport: (_, __, body) async {
          payloads.add(body);
          return {
            'choices': [
              {
                'message': {'content': 'He leído Registro2026, fila 2.'},
              },
            ],
          };
        },
      );
      Widget app() => MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
          client: client,
          availability: AiAvailability(
            store: aiStore,
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'test-model'},
                    ],
                  },
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mi borrador pendiente');
      await tester.tap(find.byKey(const Key('assistant-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoja de entrenamiento de ejemplo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registro2026'));
      await tester.pumpAndSettle();
      expect(payloads, isEmpty);
      await tester.ensureVisible(find.text('Cargar y analizar'));
      await tester.tap(find.text('Cargar y analizar'));
      await tester.pumpAndSettle();
      expect(payloads, hasLength(1));
      final system = payloads.single['messages'][0]['content'] as String;
      expect(system, contains('25×8F/lado'));
      expect(system, contains('9 + 1 parcial'));
      expect(system, contains('reps desconocidas'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mi borrador pendiente',
      );
      expect((await sheetStore.load())!.rows, rows);
      expect(await tester.runAsync(() => repo.load()), isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Hoja · Registro2026'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        '¿Qué hice en remo unilateral?',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(payloads, hasLength(2));
      expect(payloads.last['messages'][0]['content'], contains('25×8F/lado'));

      failRefresh = true;
      await tester.tap(find.byKey(const Key('assistant-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar hoja'));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión con Google.'), findsOneWidget);
      expect((await sheetStore.load())!.rows, rows);
      expect(payloads, hasLength(2));

      await tester.tap(find.byKey(const Key('assistant-sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar del contexto'));
      await tester.pumpAndSettle();
      expect(await sheetStore.load(), isNull);
      await tester.enterText(
        find.byType(TextField),
        '¿Tienes una hoja cargada?',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(
        payloads.last['messages'][0]['content'],
        contains('"googleSheet":null'),
      );
    },
  );

  testWidgets('assistant home fits a phone screen without layout errors', (
    tester,
  ) async {
    if (const bool.fromEnvironment('GYMIA_CAPTURE')) {
      await tester.runAsync(() async {
        for (final entry
            in {
              'Roboto':
                  '.tools/flutter/engine/src/flutter/third_party/txt/third_party/fonts/Roboto-Regular.ttf',
              'Ahem':
                  '.tools/flutter/engine/src/flutter/third_party/txt/third_party/fonts/Roboto-Regular.ttf',
              'MaterialIcons':
                  '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            }.entries) {
          final loader = FontLoader(entry.key);
          loader.addFont(
            File(entry.value).readAsBytes().then(ByteData.sublistView),
          );
          await loader.load();
        }
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const capture = Key('home-capture');
    await tester.pumpWidget(
      RepaintBoundary(key: capture, child: GymApp(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-talk')), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('GYMIA_CAPTURE')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 1);
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/private/tmp/gymia-assistant-home.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    }
  });

  testWidgets('unavailable microphone recognition preserves text input', (
    tester,
  ) async {
    const voiceChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(voiceChannel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(voiceChannel, null),
    );
    await const AiSettingsStore().save(config);
    await const AiSettingsStore().markVerified(config);
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
          availability: AiAvailability(
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'test-model'},
                    ],
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mi borrador');
    await tester.tap(find.byKey(const Key('assistant-talk')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El reconocimiento de voz no está disponible'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Mi borrador',
    );
  });

  testWidgets(
    'fresh home disables assistant and training but keeps data access',
    (tester) async {
      await tester.pumpWidget(GymApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Hablar con el asistente'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('assistant-talk')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('choose-activity')), findsNothing);
      expect(find.byKey(const Key('open-training')), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('assistant-attach')))
            .onPressed,
        isNotNull,
      );
      expect(find.text('Configurar IA'), findsOneWidget);
      const imports = MethodChannel('com.gymia.app/import');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(imports, (call) async {
            if (call.method != 'pickSheet') return null;
            return {
              'name': 'Mi formato.csv',
              'bytes': Uint8List.fromList(
                utf8.encode('Mi plan;\nRodilla;10 min caminando'),
              ),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(imports, null),
      );
      await tester.tap(find.byKey(const Key('assistant-attach')));
      await tester.pumpAndSettle();
      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('Documento PDF'), findsOneWidget);
      expect(find.text('Google Sheets / Drive'), findsOneWidget);
      await tester.tap(find.text('Hoja Excel o CSV'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cargar hoja'));
      await tester.tap(find.text('Cargar hoja'));
      await tester.pumpAndSettle();
      final loaded = (await const SheetContextStore().load())!;
      expect(loaded.rows[1], ['Rodilla', '10 min caminando']);
      expect(loaded.interpretationPending, isTrue);
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  test(
    'configuration can be stored and removed without entering training backups',
    () async {
      const store = AiSettingsStore();
      await store.save(config);
      expect((await store.load())?.apiKey, 'test-secret');
      expect(await repo.createBackupJson(), isNot(contains('test-secret')));
      await store.delete();
      expect(await store.load(), isNull);
    },
  );

  testWidgets(
    'conversation uses configured provider and survives reopening without mutating workouts',
    (tester) async {
      await const AiSettingsStore().save(config);
      await const AiSettingsStore().markVerified(config);
      final sessions = <String>[];
      final client = AiClient(
        transport: (uri, headers, body) async {
          expect(uri.host, 'opencode.ai');
          sessions.add(headers['x-opencode-session']!);
          final context = (body['messages'] as List).first['content'] as String;
          expect(context, contains('no tienes herramientas para registrar'));
          return {
            'choices': [
              {
                'message': {'content': 'Hola, ¿qué entrenamos hoy?'},
              },
            ],
          };
        },
      );
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: AssistantChatScreen(
              controller: controller,
              client: client,
              availability: AiAvailability(
                catalog: AiModelCatalog(
                  transport:
                      (_, __) async => {
                        'data': [
                          {'id': 'test-model'},
                        ],
                      },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(find.byType(TextField), 'Hola');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, ¿qué entrenamos hoy?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open();
      expect(find.text('Hola, ¿qué entrenamos hoy?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Cuéntame más');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(sessions.length, 2);
      expect(sessions.first, sessions.last);
      expect(await tester.runAsync(() => repo.load()), isEmpty);
    },
  );

  testWidgets('missing configuration does not invoke API and keeps draft', (
    tester,
  ) async {
    var called = false;
    final client = AiClient(
      transport: (_, __, ___) async {
        called = true;
        return {};
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
          client: client,
          availability: AiAvailability(
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'test-model'},
                    ],
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.textContaining('Configura tu proveedor'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });
}
