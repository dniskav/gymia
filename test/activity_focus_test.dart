import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/app.dart';
import 'package:gymia/ui/activity_focus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController c;
  late DateTime now;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await const AiSettingsStore().save(
      const AiConfig(
        service: AiService.custom,
        protocol: AiProtocol.chatCompletions,
        baseUrl: 'https://example.test/v1',
        model: 'test',
        apiKey: 'test-key',
      ),
    );
    await const AiSettingsStore().markVerified(
      (await const AiSettingsStore().load())!,
    );
    now = DateTime(2026, 10, 8, 10);
    dir = await Directory.systemTemp.createTemp('gymia-focus-ui-');
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.sqlite',
      clock: () => now,
    );
    c = WorkoutController(repo, clock: () => now);
    await repo.prepareActivity(
      ActivityDefinition(
        name: 'Pec Fly',
        restSeconds: 120,
        fields: const [
          {'key': 'weight_kg', 'label': 'Peso', 'unit': 'kg'},
          {'key': 'reps', 'label': 'Reps', 'unit': ''},
          {'key': 'failure', 'label': 'Fallo', 'unit': ''},
        ],
      ),
    );
    await repo.startInterval((await repo.loadActivities()).single.id);
    now = now.add(const Duration(seconds: 30));
    await repo.stopInterval((await repo.loadActivities()).single.id);
    await c.refresh();
  });
  tearDown(() async {
    c.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester, {AiClient? client}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: gymTheme,
        home: AssistantChatScreen(
          controller: c,
          client: client,
          availability: AiAvailability(
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'test'},
                    ],
                  },
            ),
          ),
          focusMode: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tap(WidgetTester tester, Key key) =>
      tester.runAsync(() => tester.tap(find.byKey(key)));
  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Drain both real SQLite completions and fake-frame continuations from the
    // final autosave before closing the database in tearDown.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'one primary control saves result locally and rest never gates restart',
    (tester) async {
      await show(tester);
      expect(find.text('Iniciar'), findsOneWidget);
      expect(find.text('Añadir serie'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      now = now.add(const Duration(seconds: 100));
      await tap(tester, const Key('activity-start-stop'));
      await waitFor(tester, () => c.focus!.running != null && !c.busy);
      expect(c.focus!.messages, isEmpty);
      expect(c.focus!.restEndsAt, isNull);
      expect(find.text('Parar'), findsOneWidget);
      now = now.add(const Duration(seconds: 30));
      await tester.enterText(find.byType(TextField), '60k 13r f');
      await tester.pump();
      expect(find.text('Parar'), findsOneWidget);
      await tap(tester, const Key('activity-start-stop'));
      await waitFor(
        tester,
        () =>
            c.focus!.running == null && !c.busy && c.focus!.messages.isNotEmpty,
      );
      expect(c.focus!.restEndsAt, now.add(const Duration(seconds: 120)));
      expect(c.focus!.messages.single.text, '60k 13r f');
      expect(c.focus!.messages.single.intervalId, c.focus!.intervals.last.id);
      await disposeScreen(tester);
    },
  );

  testWidgets(
    'small phone hides Iniciar while composing and keeps input visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await show(tester);
      await tester.enterText(find.byType(TextField), 'Me molestó el hombro');
      expect(find.byType(ListView), findsOneWidget);
      await tester.pump();
      expect(find.byKey(const Key('activity-start-stop')), findsNothing);
      final input = tester.getRect(find.byType(TextField));
      expect(input.bottom, lessThanOrEqualTo(340));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 350));
      await waitFor(tester, () => !c.busy);
      await disposeScreen(tester);
      expect(
        (await tester.runAsync(() => repo.loadActivities()))!.single.draft,
        'Me molestó el hombro',
      );
    },
  );
  testWidgets(
    'chat focus and pending draft hide Iniciar until communication ends',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await show(tester);
      final start = find.byKey(const Key('activity-start-stop'));
      final input = find.byKey(const Key('assistant-input'));
      expect(start, findsOneWidget);
      await tester.showKeyboard(input);
      await tester.pump();
      expect(start, findsNothing);
      await tester.enterText(input, '60k 13r f');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(start, findsNothing); // Draft still awaiting Send.
      expect(c.focus!.running, isNull);
      await tester.enterText(input, '');
      await tester.pump();
      expect(start, findsNothing); // Focus alone is enough.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        start,
        findsOneWidget,
      ); // Back/dismissing the keyboard ends editing.
      expect(c.focus!.running, isNull);
      await disposeScreen(tester);
    },
  );

  testWidgets('dictation hides Iniciar and restores it when cancelled', (
    tester,
  ) async {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'initialize' => true,
            'locales' => ['es_ES:Español'],
            'listen' => true,
            'stop' || 'cancel' => null,
            _ => null,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await show(tester);
    expect(find.text('Iniciar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-talk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-start-stop')), findsNothing);
    expect(find.byTooltip('Terminar dictado'), findsOneWidget);
    expect(c.focus!.running, isNull);
    await tester.tap(find.byKey(const Key('assistant-talk')));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar'), findsOneWidget);
    expect(c.focus!.running, isNull);
    await tester.pump(
      const Duration(seconds: 3),
    ); // Drain the recognizer final-result timeout.
    await disposeScreen(tester);
  });

  testWidgets(
    'unambiguous shorthand uses local receipt and never calls the LLM',
    (tester) async {
      var calls = 0;
      await const AiSettingsStore().save(
        const AiConfig(
          service: AiService.custom,
          protocol: AiProtocol.chatCompletions,
          baseUrl: 'https://example.test/v1',
          model: 'test',
          apiKey: 'test-key',
        ),
      );
      await show(
        tester,
        client: AiClient(
          transport: (_, __, ___) async {
            calls++;
            throw StateError('No model is needed');
          },
        ),
      );
      await tester.enterText(find.byType(TextField), '60k13rf');
      await tester.runAsync(() => tester.tap(find.byTooltip('Enviar')));
      await waitFor(tester, () => c.focus!.messages.length == 2);
      expect(c.focus!.messages.first.metrics['reps'], 13);
      expect(c.focus!.messages.last.role, 'assistant');
      expect(calls, 0);
      expect(find.textContaining('60 kg × 13 · fallo · fin'), findsOneWidget);
      await disposeScreen(tester);
      await show(tester);
      expect(find.textContaining('60 kg × 13 · fallo · fin'), findsOneWidget);
      expect(calls, 0);
      await disposeScreen(tester);
    },
  );
  testWidgets(
    'opening keyboard preserves composer focus and receives the complete text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await show(tester);
      await tester.showKeyboard(find.byKey(const Key('assistant-input')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'Pr'),
      );
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding(bottom: 300);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'Prueba completa'),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('assistant-input')))
            .controller!
            .text,
        'Prueba completa',
      );
      expect(tester.takeException(), isNull);
      await disposeScreen(tester);
    },
  );

  testWidgets(
    'delayed LLM interpretation stays with original activity after Terminar',
    (tester) async {
      final answer = Completer<Map<String, dynamic>>();
      var called = false;
      await const AiSettingsStore().save(
        const AiConfig(
          service: AiService.custom,
          protocol: AiProtocol.chatCompletions,
          baseUrl: 'https://example.test/v1',
          model: 'test',
          apiKey: 'test-key',
        ),
      );
      await show(
        tester,
        client: AiClient(
          transport: (_, __, body) async {
            called = true;
            return answer.future;
          },
        ),
      );
      final original = c.focus!.id;
      await tester.enterText(
        find.byType(TextField),
        'Hoy me molestó la rodilla',
      );
      await tester.runAsync(() => tester.tap(find.byTooltip('Enviar')));
      await waitFor(tester, () => called && c.focus!.messages.isNotEmpty);
      await tap(tester, const Key('finish-activity'));
      for (var i = 0; i < 30 && find.text('Guardar').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => tester.tap(find.text('Guardar')));
      await waitFor(tester, () => c.focus == null && !c.busy);
      await tester.runAsync(() async {
        await repo.prepareActivity(
          ActivityDefinition(name: 'Fútbol', repeated: false, restSeconds: 0),
        );
        await c.refresh();
        answer.complete({
          'choices': [
            {
              'message': {
                'content': 'Conservaré esa observación junto al Pec Fly.',
              },
            },
          ],
        });
      });
      await waitFor(
        tester,
        () =>
            c.activities.singleWhere((a) => a.id == original).messages.length ==
            2,
      );
      expect(c.focus!.definition.name, 'Fútbol');
      expect(c.focus!.messages, isEmpty);
      expect(
        c.activities.singleWhere((a) => a.id == original).messages.first.text,
        'Hoy me molestó la rodilla',
      );
      await disposeScreen(tester);
    },
  );
  testWidgets(
    'LLM prepares flexible activity automatically; only Iniciar starts timing',
    (tester) async {
      await tester.runAsync(() async {
        await repo.finishActivity(c.focus!.id, now);
        await c.refresh();
      });
      await const AiSettingsStore().save(
        const AiConfig(
          service: AiService.custom,
          protocol: AiProtocol.chatCompletions,
          baseUrl: 'https://example.test/v1',
          model: 'test',
          apiKey: 'test-key',
        ),
      );
      await show(
        tester,
        client: AiClient(
          transport:
              (_, __, body) async => {
                'choices': [
                  {
                    'message': {
                      'content':
                          'Prepararemos fútbol.\n```gymia-activity\n{"name":"Fútbol","repeated":false,"restSeconds":0,"fields":[{"key":"goals","label":"Goles","unit":""}],"instructions":"Consultar notas de rodilla anteriores"}\n```',
                    },
                  },
                ],
              },
        ),
      );
      await tester.enterText(find.byType(TextField), 'Voy a jugar fútbol');
      await tester.runAsync(() => tester.tap(find.byTooltip('Enviar')));
      await waitFor(tester, () => c.focus != null && !c.busy);
      expect(c.focus!.definition.name, 'Fútbol');
      expect(c.focus!.definition.fields.single['key'], 'goals');
      expect(c.focus!.intervals, isEmpty);
      await tap(tester, const Key('activity-start-stop'));
      await waitFor(tester, () => c.focus!.running != null && !c.busy);
      expect(find.text('Parar'), findsOneWidget);
      await disposeScreen(tester);
    },
  );
  testWidgets('canceling change keeps prepared activity and its footer', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await repo.finishActivity(c.focus!.id, now);
      await repo.prepareActivity(
        ActivityDefinition(name: 'Chest Press · prueba'),
      );
      await c.refresh();
    });
    await show(tester);
    final id = c.focus!.id;
    await tap(tester, const Key('change-activity'));
    for (
      var i = 0;
      i < 100 && find.byType(ActivityChooser).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(ActivityChooser), findsOneWidget);
    expect(c.focus!.id, id);
    await tester.runAsync(() async {
      Navigator.of(tester.element(find.byType(ActivityChooser))).pop();
    });
    await tester.pumpAndSettle();
    expect(c.focus!.id, id);
    expect(find.byKey(const Key('activity-start-stop')), findsOneWidget);
    await tap(tester, const Key('rename-activity'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('activity-name-input')),
      'Prueba renombrada',
    );
    await tester.runAsync(() => tester.tap(find.text('Guardar nombre')));
    await waitFor(
      tester,
      () => c.focus!.definition.name == 'Prueba renombrada',
    );
    expect(c.focus!.id, id);
    expect(c.focus!.intervals, isEmpty);
    await disposeScreen(tester);
  });

  testWidgets('new preparation does not inherit an expired finished rest', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await repo.finishActivity(c.focus!.id, now);
      now = now.add(const Duration(seconds: 121));
      await repo.prepareActivity(
        ActivityDefinition(name: 'Nueva actividad', restSeconds: 180),
      );
      await c.refresh();
    });
    await show(tester);
    expect(find.text('180s'), findsOneWidget);
    expect(find.text('0:00 · 120s'), findsNothing);
    await disposeScreen(tester);
  });

  testWidgets('idle and prepared footer keep the same button positions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await repo.finishActivity(c.focus!.id, now);
      now = now.add(const Duration(seconds: 121));
      await c.refresh();
    });
    await show(tester);
    final start = tester.getRect(find.byKey(const Key('activity-start-stop')));
    final finish = tester.getRect(find.byKey(const Key('finish-activity')));
    expect(find.text('Sin actividad'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activity-start-stop')))
          .onPressed,
      isNull,
    );
    await tester.runAsync(() async {
      await repo.prepareActivity(ActivityDefinition(name: 'Chest Press'));
      await c.refresh();
    });
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('activity-start-stop'))), start);
    expect(tester.getRect(find.byKey(const Key('finish-activity'))), finish);
    expect(find.text('Chest Press'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('activity-start-stop')))
          .onPressed,
      isNotNull,
    );
    await disposeScreen(tester);
  });
}
