import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_sync_service.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/sheet_sync.dart';
import 'package:gymia/ui/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android uses saved Google grant, reads current data, maps layout and sends on completion',
    (tester) async {
      tester.testTextInput.register();
      const storage = FlutterSecureStorage();
      const keys = [
        'gymia.profiles.v1',
        'gymia.ai.config.v1',
        'gymia.ai.config.v1.verified',
        'gymia.ai.chat.v1',
        'gymia.sheet.context.v1',
        'gymia.sheet.destination.v1',
        'gymia.sheet.creation.v1',
        'gymia.sheet.connection.v1',
        'gymia.sheet.jobs.v1',
      ];
      final saved = <String, String?>{};
      for (final key in keys) {
        saved[key] = await storage.read(key: key);
        await storage.delete(key: key);
      }
      await ProfileStore.instance.load();
      final dir = await Directory.systemTemp.createTemp(
        'gymia-sheet-auto-android-',
      );
      final repo = await SqliteWorkoutRepository.open(
        path: '${dir.path}/qa.sqlite',
      );
      final id = await repo.start('Primera sesión');
      await repo.addExercise(id, 'Press');
      await repo.addSet(
        (await repo.load()).single.exercises.single.id,
        '60',
        '10',
      );
      await repo.finish(id, acceptTimeConflicts: true);
      final controller = WorkoutController(repo);
      await controller.refresh();
      const config = AiConfig(
        service: AiService.custom,
        protocol: AiProtocol.chatCompletions,
        baseUrl: 'https://example.test/v1',
        model: 'qa',
        apiKey: 'fake',
      );
      await const AiSettingsStore().save(config);
      await const AiSettingsStore().markVerified(config);
      const dest = UserProfile(
        subject: 'qa-existing-account',
        email: 'qa@example.test',
      );
      await storage.write(
        key: 'gymia.sheet.destination.v1',
        value: jsonEncode(dest.toJson()),
      );
      final snapshot = <String, dynamic>{
        'rows': [
          ['Fecha', 'Press', 'Carga'],
          ['último dato remoto'],
        ],
        'occupied': ['0:0', '0:1', '0:2', '1:0', '41:4'],
        'entered': {
          '41:4': {'formulaValue': '=SUM(C42:D42)'},
        },
        'merges': <dynamic>[],
        'properties': {
          'sheetId': 7,
          'title': 'Resumen 2026',
          'gridProperties': {'rowCount': 1000, 'columnCount': 26},
        },
      };
      final service = SheetSyncService(profileId: 'local')..identity = dest;
      await service.bind(
        SheetContext(
          id: 'qa-sheet',
          name: 'Progreso',
          title: 'Resumen 2026',
          loadedAt: DateTime(2026, 10, 1),
          rows: const [
            ['copia antigua'],
          ],
        ),
        snapshot,
        allowOverwrite: true,
      );
      final calls = <MethodCall>[];
      final receipts = <String>{};
      var expireRead = true;
      var userCalls = 0, planningCalls = 0;
      // Controlled Google transport; native secure storage, SQLite, IME and widgets.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            calls.add(call);
            final args = call.arguments as Map? ?? {};
            switch (call.method) {
              case 'authorizeWrite':
                if (args['interactive'] != false) {
                  throw StateError('Unexpected interactive authorization');
                }
                return true;
              case 'clearSheetToken':
                return null;
              case 'syncStatus':
                return {'synced': receipts.contains(args['sourceKey'])};
              case 'syncSnapshot':
                if (expireRead) {
                  expireRead = false;
                  throw PlatformException(code: 'GOOGLE_AUTH_REQUIRED');
                }
                return snapshot;
              case 'writeWorkout':
                receipts.add(args['sourceKey'] as String);
                return {'synced': true};
            }
            throw StateError(
              'Unexpected interactive Google operation ${call.method}',
            );
          });
      final availability = AiAvailability(
        catalog: AiModelCatalog(
          transport:
              (_, __) async => {
                'data': [
                  {'id': 'qa'},
                ],
              },
        ),
      );
      final client = AiClient(
        transport: (_, __, body) async {
          final request = jsonEncode(body);
          if (!request.contains('último dato remoto')) {
            throw StateError('The model received stale sheet data');
          }
          String text;
          if (request.contains('Eres el intérprete de la hoja')) {
            final row = 42 + planningCalls++;
            text =
                '```gymia-sheet-plan\n${jsonEncode({
                  'summary': 'Resultados en el bloque propio de Press',
                  'layout': 'Bloque de octubre: carga C, repeticiones D',
                  'writes': [
                    {'cell': 'C$row', 'value': 60},
                    {'cell': 'D$row', 'value': 10},
                  ],
                })}\n```';
          } else {
            userCalls++;
            text =
                userCalls == 1
                    ? 'Envío los datos a su sitio.\n```gymia-sync\n{"workoutId":"$id"}\n```'
                    : '> La hoja se ha consultado con los datos actuales.\n>\n> Tu progreso sigue disponible.';
          }
          return {
            'choices': [
              {
                'message': {'content': text},
              },
            ],
          };
        },
      );
      Future<void> drain() async {
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: gymTheme,
            home: AssistantChatScreen(
              controller: controller,
              client: client,
              availability: availability,
              focusMode: true,
            ),
          ),
        );
        await drain();
        await tester.enterText(
          find.byType(TextField).last,
          'Actualiza mi hoja con los resultados.',
        );
        await tester.tap(find.byTooltip('Enviar'));
        await drain();
        expect(find.byType(SheetSyncScreen), findsNothing);
        expect(calls.where((c) => c.method == 'writeWorkout'), hasLength(1));
        expect(calls.where((c) => c.method == 'clearSheetToken'), hasLength(1));
        final firstWrite =
            calls.singleWhere((c) => c.method == 'writeWorkout').arguments
                as Map;
        expect(
          (firstWrite['writes'] as List).map((c) => [c['row'], c['column']]),
          [
            [41, 2],
            [41, 3],
          ],
        );
        expect((await service.connection())!['layout'], contains('octubre'));
        // A newly completed session is queued and sent without another user command.
        await controller.run(() async {
          final next = await repo.start('Segunda sesión');
          await repo.addExercise(next, 'Press');
          await repo.addSet(
            (await repo.load())
                .firstWhere((w) => w.id == next)
                .exercises
                .single
                .id,
            '60',
            '10',
          );
          await repo.finish(next, acceptTimeConflicts: true);
        });
        await drain();
        expect(
          calls.where((c) => c.method == 'writeWorkout'),
          hasLength(2),
          reason:
              'jobs=${await storage.read(key: 'gymia.sheet.jobs.v1')}, config=${await service.connection()}',
        );
        expect(calls.where((c) => c.method == 'connectIdentity'), isEmpty);
        expect((await repo.load()), hasLength(2));
        await tester.enterText(
          find.byType(TextField).last,
          '¿Cómo va mi progreso?',
        );
        await tester.tap(find.byTooltip('Enviar'));
        await drain();
        if (const bool.fromEnvironment('GYMIA_VISUAL_QA')) {
          debugPrint('GYMIA_QUOTE_PREVIEW_READY');
          await Future<void>.delayed(const Duration(seconds: 12));
        }
        expect(userCalls, 2);
        expect(planningCalls, 2);
        expect(tester.takeException(), null);
        expect(
          jsonEncode(
            jsonDecode((await storage.read(key: 'gymia.ai.chat.v1'))!),
          ),
          contains('Google Sheets confirmado'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        availability.dispose();
        controller.dispose();
        await repo.close();
        await dir.delete(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ProfileStore.channel, null);
        for (final key in keys) {
          final value = saved[key];
          if (value == null) {
            await storage.delete(key: key);
          } else {
            await storage.write(key: key, value: value);
          }
        }
        await ProfileStore.instance.load();
      }
    },
  );
}
