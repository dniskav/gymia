import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/app.dart';
import 'package:gymia/ui/activity_focus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android chat, two activity types, rest, offline stop and recovery', (
    tester,
  ) async {
    // IntegrationTest leaves the real IME attached. Register the driver input
    // to prevent Android echoing an old value over tester.enterText(). Native
    // keyboard entry is checked separately with adb on the installed app.
    tester.testTextInput.register();
    // Controlled provider replies exercise the actual UI, SQLite and secure
    // storage on Android. This is not a live LLM/provider validation.
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
    final dir = await Directory.systemTemp.createTemp('gymia-chat-qa-');
    var repo = await SqliteWorkoutRepository.open(
      path: '${dir.path}/qa.sqlite',
    );
    var c = WorkoutController(repo);
    var calls = 0;
    final client = AiClient(
      transport: (_, __, body) async {
        calls++;
        final text = (body['messages'] as List).last['content'] as String;
        final reply = switch (text) {
          'Empezamos día de push' =>
            '¿Empezamos con **Chest Press** o Pec Fly?',
          'Empezamos con Chest Press' =>
            'Listo, empieza con **60 kg**.\n'
                '```gymia-activity\n'
                '{"name":"Chest Press · prueba","repeated":true,"restSeconds":120,'
                '"fields":[{"key":"weight_kg","label":"Peso","unit":"kg"},'
                '{"key":"reps","label":"Reps","unit":""},'
                '{"key":"failure","label":"Fallo","unit":""}]}'
                '\n```',
          '60 10' => '¿Fueron 60 kg y 10 repeticiones? ¿Al fallo?',
          'Voy a jugar fútbol' =>
            'Listo para el partido.\n'
                '```gymia-activity\n'
                '{"name":"Fútbol · prueba","repeated":false,"restSeconds":0,'
                '"fields":[{"key":"goals","label":"Goles","unit":""},'
                '{"key":"assists","label":"Asistencias","unit":""}]}'
                '\n```',
          '2 goles y una asistencia; me molestó la rodilla' =>
            'Registrados 2 goles y 1 asistencia. Conservo la nota de rodilla.\n'
                '```gymia-result\n{"metrics":{"goals":2,"assists":1}}\n```',
          _ => throw StateError('Unexpected QA message'),
        };
        return {
          'choices': [
            {
              'message': {'content': reply},
            },
          ],
        };
      },
    );
    final availability = AiAvailability(
      catalog: AiModelCatalog(
        transport:
            (_, __) async => {
              'data': [
                {'id': 'qa-model'},
              ],
            },
      ),
    );
    const config = AiConfig(
      service: AiService.custom,
      baseUrl: 'https://example.test/v1',
      model: 'qa-model',
      protocol: AiProtocol.chatCompletions,
      apiKey: 'qa-fixture-not-a-real-key',
    );
    Future<void> until(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue);
    }

    bool sendEnabled() =>
        tester
            .widgetList<IconButton>(find.byType(IconButton))
            .singleWhere((button) => button.tooltip == 'Enviar')
            .onPressed !=
        null;
    Future<void> mount() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: gymTheme,
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AssistantChatScreen(
            controller: c,
            client: client,
            availability: availability,
            focusMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await until(() => availability.ready && sendEnabled());
    }

    Future<void> send(String text) async {
      await tester.enterText(find.byKey(const Key('assistant-input')), text);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        text,
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await until(
        () =>
            sendEnabled() &&
            tester
                .widget<TextField>(find.byKey(const Key('assistant-input')))
                .controller!
                .text
                .isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
    }

    Future<void> press(Key key) async {
      await tester.tap(find.byKey(key));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await until(() => !c.busy);
    }

    Future<void> finish() async {
      tester.testTextInput.hide();
      await press(const Key('finish-activity'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      await until(() => c.focus == null);
      expect(c.focus, isNull);
    }

    try {
      await const AiSettingsStore().save(config);
      await const AiSettingsStore().markVerified(config);
      await c.refresh();
      await mount();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activity-start-stop')))
            .onPressed,
        isNull,
      );
      await send('Empezamos día de push');
      expect(calls, 1);
      expect(c.focus, isNull);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('activity-start-stop')))
            .onPressed,
        isNull,
      );
      await send('Empezamos con Chest Press');
      expect(calls, 2);
      expect(c.focus, isNotNull, reason: 'Preparation error: ${c.error}');
      expect(c.focus!.definition.name, 'Chest Press · prueba');
      expect(c.focus!.intervals, isEmpty);
      final preparedId = c.focus!.id;
      await press(const Key('rename-activity'));
      await tester.enterText(
        find.byKey(const Key('activity-name-input')),
        'Chest Press · QA renombrada',
      );
      await tester.tap(find.text('Guardar nombre'));
      await until(
        () => c.focus!.definition.name == 'Chest Press · QA renombrada',
      );
      await tester.pumpAndSettle();
      expect(c.focus!.id, preparedId);
      await press(const Key('change-activity'));
      await until(() => find.byType(ActivityChooser).evaluate().isNotEmpty);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(c.focus!.id, preparedId);
      expect(find.byKey(const Key('activity-start-stop')), findsOneWidget);
      await press(const Key('activity-start-stop'));
      expect(c.focus!.running, isNotNull);
      await tester.pump(const Duration(seconds: 1));
      await press(const Key('activity-start-stop'));
      expect(c.focus!.running, isNull);
      expect(c.focus!.restEndsAt!.isAfter(c.now()), isTrue);
      await send('60 10');
      expect(c.focus!.messages.first.metrics, isEmpty);
      final before = calls;
      await send('60k 13r f');
      expect(calls, before);
      expect(
        c.focus!.messages.where((m) => m.role == 'user').last.metrics['reps'],
        13,
      );
      expect(c.focus!.messages.last.text, contains('fin '));
      // Restart before the rest deadline is allowed.
      await press(const Key('activity-start-stop'));
      expect(c.focus!.running, isNotNull);
      expect(c.focus!.restEndsAt, isNull);
      await press(const Key('activity-start-stop'));
      await finish();
      expect(
        c.active,
        isNotNull,
      ); // Ending the exercise does not close the day.
      await send('Voy a jugar fútbol');
      expect(c.focus!.definition.repeated, isFalse);
      expect(
        c.focus!.definition.fields.any((f) => f['key'] == 'reps'),
        isFalse,
      );
      await press(const Key('activity-start-stop'));
      await send('2 goles y una asistencia; me molestó la rodilla');
      expect(c.focus!.messages.first.metrics['goals'], 2);
      expect(c.focus!.messages.first.text, contains('molestó la rodilla'));
      // Removing the connection must not strand a running activity.
      await const AiSettingsStore().delete();
      await availability.check();
      await tester.pumpAndSettle();
      await press(const Key('activity-start-stop'));
      expect(c.focus!.running, isNull);
      await finish();
      expect(c.activities, hasLength(2));
      expect(c.activities.every((a) => !a.active), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await repo.close();
      repo = await SqliteWorkoutRepository.open(path: '${dir.path}/qa.sqlite');
      c = WorkoutController(repo);
      await c.refresh();
      expect(c.activities, hasLength(2));
      expect(
        c.activities.singleWhere((a) => a.definition.repeated).intervals,
        hasLength(2),
      );
      expect(
        c.activities
            .singleWhere((a) => !a.definition.repeated)
            .messages
            .first
            .metrics['assists'],
        1,
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await repo.close();
      await dir.delete(recursive: true);
      for (final key in keys) {
        if (saved[key] == null) {
          await storage.delete(key: key);
        } else {
          await storage.write(key: key, value: saved[key]);
        }
      }
      tester.testTextInput.unregister();
    }
  });
}
