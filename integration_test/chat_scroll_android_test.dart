import 'dart:async';
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
import 'package:gymia/data/chat_archive_store.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/chat_message.dart';
import 'package:gymia/ui/app.dart';

class _ScrollClient extends AiClient {
  final completed = Completer<String>();
  void Function(String)? emit;
  final responses = <String>[];
  @override
  Future<String> reply(
    AiConfig config,
    List<AiMessage> messages, {
    required String system,
    required String sessionId,
    void Function(String)? onText,
  }) {
    if (responses.isNotEmpty) return Future.value(responses.removeAt(0));
    emit = onText;
    return completed.future;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android follows newest messages through history, streaming, IME and local records',
    (tester) async {
      tester.testTextInput.register();
      const storage = FlutterSecureStorage();
      const keys = [
        'gymia.ai.config.v1',
        'gymia.ai.config.v1.verified',
        'gymia.ai.chat.v1',
        'gymia.sheet.context.v1',
      ];
      final saved = <String, String?>{};
      for (final key in keys) {
        saved[key] = await storage.read(key: key);
        await storage.delete(key: key);
      }
      final dir = await Directory.systemTemp.createTemp(
        'gymia-scroll-android-',
      );
      final repo = await SqliteWorkoutRepository.open(
        path: '${dir.path}/qa.sqlite',
      );
      final controller = WorkoutController(repo);
      final client = _ScrollClient();
      final availability = AiAvailability(
        catalog: AiModelCatalog(
          transport:
              (_, __) async => {
                'data': [
                  {'id': 'qa-scroll'},
                ],
              },
        ),
      );
      try {
        await const AiSettingsStore().save(
          const AiConfig(
            service: AiService.custom,
            protocol: AiProtocol.chatCompletions,
            baseUrl: 'https://example.test/v1',
            model: 'qa-scroll',
            apiKey: 'fixture-no-real-key',
          ),
        );
        await const AiSettingsStore().markVerified(
          (await const AiSettingsStore().load())!,
        );
        await storage.write(
          key: 'gymia.ai.chat.v1',
          value: jsonEncode({
            'sessionId': 'android-scroll-qa',
            'messages': [
              for (var i = 0; i < 90; i++)
                AiMessage(
                  'assistant',
                  'Histórico $i\n${List.filled(1 + i % 12, 'Detalle variable del entrenamiento.').join('\n')}',
                ).forStorage(),
            ],
          }),
        );
        await controller.refresh();
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
        await tester.pumpAndSettle();
        final list = find.byKey(const Key('assistant-transcript'));
        final scroll = tester.widget<ListView>(list).controller!;
        void atEnd() => expect(scroll.position.extentAfter, lessThan(1));
        Future<void> frames() async {
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }

        atEnd();
        await tester.drag(list, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, greaterThan(100));
        // Refreshing unchanged records must not interrupt history reading.
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, greaterThan(100));
        await tester.enterText(
          find.byKey(const Key('assistant-input')),
          'Consulta de prueba',
        );
        await tester.tap(find.byTooltip('Enviar'));
        await frames();
        expect(client.emit, isNotNull);
        atEnd();
        var text = '';
        for (var i = 0; i < 4; i++) {
          if (i == 1) {
            await tester.drag(list, const Offset(0, 400));
            await frames();
          }
          final beforeChunk = scroll.position.pixels;
          text += List.filled(
            14,
            '**Bloque $i**\n\nRespuesta progresiva con altura variable.',
          ).join('\n\n');
          client.emit!(text);
          await frames();
          if (i == 1) {
            expect(scroll.position.extentAfter, greaterThan(100));
            expect(scroll.position.pixels, closeTo(beforeChunk, 1));
            await tester.tap(find.byKey(const Key('chat-latest')));
            await frames();
          }
          atEnd();
        }
        client.completed.complete('$text\n\nÚltima línea de la respuesta.');
        await tester.pumpAndSettle();
        atEnd();
        // Exercise the Android IME through the native text input channel.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        tester.testTextInput.unregister();
        await tester.tap(find.byKey(const Key('assistant-input')));
        for (var i = 0; i < 60 && tester.view.viewInsets.bottom == 0; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await frames();
        expect(tester.view.viewInsets.bottom, greaterThan(0));
        atEnd();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        FocusManager.instance.primaryFocus?.unfocus();
        await frames();
        atEnd();
        await repo.prepareActivity(
          ActivityDefinition(name: 'Actividad de prueba'),
        );
        await controller.refresh();
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, greaterThan(100));
        await repo.recordActivityMessage(
          controller.focus!.id,
          'Confirmación local más reciente.',
          role: 'assistant',
        );
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(scroll.position.extentAfter, greaterThan(100));
        await tester.tap(find.byKey(const Key('chat-latest')));
        await tester.pumpAndSettle();
        atEnd();
        final latest = find.byWidgetPredicate(
          (widget) =>
              widget is ChatMessageBody &&
              widget.text == 'Confirmación local más reciente.',
        );
        expect(latest, findsOneWidget);
        expect(
          tester.getRect(latest).bottom,
          lessThanOrEqualTo(tester.getRect(list).bottom + 1),
        );
        expect(
          tester.getRect(latest).top,
          greaterThanOrEqualTo(tester.getRect(list).top - 1),
        );
        // While communicating, hide Start but keep Stop available.
        tester.testTextInput.register();
        final input = find.byKey(const Key('assistant-input'));
        final start = find.byKey(const Key('activity-start-stop'));
        expect(start, findsOneWidget);
        await tester.enterText(input, 'Mensaje pendiente');
        await tester.pumpAndSettle();
        expect(start, findsNothing);
        expect(controller.focus!.running, isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(start, findsNothing); // Draft still awaits sending.
        await tester.enterText(input, '');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(start, findsOneWidget);
        await tester.tap(start);
        for (var i = 0; i < 100 && controller.focus!.running == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(controller.focus!.running, isNotNull);
        await tester.enterText(input, 'Nota mientras corre el reloj');
        await tester.pumpAndSettle();
        expect(find.text('Parar'), findsOneWidget);
        await tester.tap(start);
        for (
          var i = 0;
          i < 100 &&
              !controller.focus!.messages.any(
                (m) => m.text == 'Nota mientras corre el reloj',
              );
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(controller.focus!.running, isNull);
        expect(
          controller.focus!.messages.last.text,
          'Nota mientras corre el reloj',
        );
        atEnd();
        expect(tester.takeException(), isNull);
        await repo.finishActivity(
          controller.focus!.id,
          DateTime.now(),
          acceptConflicts: true,
        );
        await controller.refresh();
        await tester.pumpAndSettle();
        // Archive a whole chat, inspect it, then let the model archive the next
        // completed exchange. None of these operations alters the workout.
        final workoutId = controller.workouts.single.id;
        await tester.tap(find.byKey(const Key('archive-chat')));
        await frames();
        await tester.pumpAndSettle();
        const archiveStore = ChatArchiveStore(profileId: 'local');
        var active = (await archiveStore.active())!;
        expect(active['messages'], isEmpty);
        expect(ChatArchiveStore.index(active), hasLength(1));
        final entry = ChatArchiveStore.index(active).single;
        final document = await archiveStore.read(entry['id'] as String);
        expect(jsonEncode(document), contains('Nota mientras corre el reloj'));
        expect(controller.workouts.single.id, workoutId);
        await tester.tap(find.byTooltip('Chats archivados'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry['title'] as String));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Consultar desde el chat'));
        await tester.pumpAndSettle();
        client.responses.add(
          'Fase completada.\n```gymia-archive\n{"title":"Fase completada","summary":"Continuamos con la siguiente actividad.","reason":"Cierre de fase"}\n```',
        );
        await tester.enterText(
          find.byKey(const Key('assistant-input')),
          'Cerramos esta fase',
        );
        await tester.tap(find.byTooltip('Enviar'));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          active = (await archiveStore.active())!;
          if (ChatArchiveStore.index(active).length == 2) break;
        }
        await tester.pumpAndSettle();
        expect(ChatArchiveStore.index(active), hasLength(2));
        expect(active['messages'], isEmpty);
        expect(controller.workouts.single.id, workoutId);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        availability.dispose();
        controller.dispose();
        await repo.close();
        const archiveStore = ChatArchiveStore(profileId: 'local');
        for (final entry in ChatArchiveStore.index(
          await archiveStore.active(),
        )) {
          await storage.delete(key: 'gymia.ai.archive.v1.${entry['id']}');
        }
        for (final key in keys) {
          if (saved[key] == null) {
            await storage.delete(key: key);
          } else {
            await storage.write(key: key, value: saved[key]);
          }
        }
        await dir.delete(recursive: true);
      }
    },
  );
}
