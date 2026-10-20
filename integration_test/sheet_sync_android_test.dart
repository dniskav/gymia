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
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/sheet_sync.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android model opens creation, previews and confirms one workout, then verifies its receipt',
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
        'gymia-sheets-android-',
      );
      final repo = await SqliteWorkoutRepository.open(
        path: '${dir.path}/qa.sqlite',
      );
      final id = await repo.start('Prueba envío Android');
      await repo.addExercise(id, 'Press');
      final exercise = (await repo.load()).single.exercises.single.id;
      await repo.addSet(exercise, '60', '10');
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
      final calls = <MethodCall>[];
      var synced = false;
      final client = AiClient(
        transport:
            (_, __, body) async => {
              'choices': [
                {
                  'message': {
                    'content':
                        'Vamos a crear la hoja y revisar el envío.\n```gymia-sync\n${jsonEncode({'workoutId': id, 'create': true, 'name': 'Progreso Android QA'})}\n```',
                  },
                },
              ],
            },
      );
      // Controlled Google transport: real Android UI, SQLite and encrypted storage;
      // does not claim a live Google OAuth or external spreadsheet write.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'connectIdentity':
                return const UserProfile(
                  subject: 'qa-destination',
                  email: 'qa@example.test',
                ).toJson();
              case 'authorizeWrite':
                return true;
              case 'list':
                return {'files': <dynamic>[], 'nextPageToken': ''};
              case 'tabs':
                return ['Entrenamientos'];
              case 'createSpreadsheet':
                return {
                  'id': 'qa-created-file',
                  'name': 'Progreso Android QA',
                  'title': 'Entrenamientos',
                };
              case 'syncStatus':
                return {'synced': synced};
              case 'syncSnapshot':
                return {
                  'rows': [canonicalHeaders],
                  'occupied': [for (var c = 0; c < 7; c++) '0:$c'],
                  'entered': <String, dynamic>{},
                  'merges': <dynamic>[],
                  'properties': {
                    'sheetId': 7,
                    'title': 'Entrenamientos',
                    'gridProperties': {'rowCount': 1000, 'columnCount': 26},
                  },
                };
              case 'writeWorkout':
                synced = true;
                return {'synced': true, 'alreadySynced': false};
            }
            throw StateError('Unexpected Google call ${call.method}');
          });
      Future<void> drain() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pumpAndSettle();
      }

      Future<void> tapKey(String key) async {
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
        await tester.tap(target);
        await drain();
      }

      try {
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
        await drain();
        await tester.enterText(
          find.byType(TextField).last,
          'Crea una hoja nueva y envía mi entrenamiento finalizado.',
        );
        await tester.tap(find.byTooltip('Enviar'));
        await drain();
        expect(find.byType(SheetSyncScreen), findsOneWidget);
        expect(
          calls.any(
            (c) =>
                c.method == 'createSpreadsheet' || c.method == 'writeWorkout',
          ),
          false,
        );
        await tapKey('sync-connect');
        await tapKey('sync-create');
        expect(
          calls.where((c) => c.method == 'createSpreadsheet'),
          hasLength(1),
        );
        expect(calls.any((c) => c.method == 'writeWorkout'), false);
        await tapKey('sync-prepare');
        expect(calls.any((c) => c.method == 'writeWorkout'), false);
        await tapKey('sync-confirm');
        expect(calls.where((c) => c.method == 'writeWorkout'), hasLength(1));
        final write =
            calls.singleWhere((c) => c.method == 'writeWorkout').arguments
                as Map;
        expect(write['expectedSubject'], 'qa-destination');
        expect(write['sourceKey'], 'local:$id');
        expect(
          (write['writes'] as List).any(
            (w) => '${w['value']}'.contains('"reps":10'),
          ),
          true,
        );
        expect((await repo.load()).single.id, id);
        expect(
          (await repo.load()).single.exercises.single.sets.single.weight,
          6000,
        );
        await tapKey('sync-prepare');
        expect(calls.where((c) => c.method == 'writeWorkout'), hasLength(1));
        final back = find.text('Volver al chat');
        await tester.scrollUntilVisible(
          back,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(back);
        await drain();
        expect(find.byType(SheetSyncScreen), findsNothing);
        final chat =
            jsonDecode((await storage.read(key: 'gymia.ai.chat.v1'))!) as Map;
        expect(jsonEncode(chat).contains('Google Sheets confirmado'), true);
        expect(ProfileStore.instance.activeId, 'local');
        expect(tester.takeException(), null);
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
