import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/ui/assistant_chat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkoutRepository repo;
  late WorkoutController controller;
  var now = DateTime(2026, 10, 8, 8, 30);
  var providerCalls = 0;

  Future<void> openRepository() async {
    repo = await SqliteWorkoutRepository.open(
      factory: databaseFactoryFfi,
      path: '${dir.path}/test.sqlite',
      clock: () => now,
    );
    controller = WorkoutController(repo, clock: () => now);
    await controller.refresh();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await const AiSettingsStore().save(
      const AiConfig(
        service: AiService.custom,
        protocol: AiProtocol.chatCompletions,
        baseUrl: 'https://example.test/v1',
        model: 'test',
        apiKey: 'fake-key',
      ),
    );
    await const AiSettingsStore().markVerified(
      (await const AiSettingsStore().load())!,
    );
    now = DateTime(2026, 10, 8, 8, 30);
    providerCalls = 0;
    dir = await Directory.systemTemp.createTemp('gymia-session-');
    await openRepository();
  });

  tearDown(() async {
    controller.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  });

  Future<void> openChat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantChatScreen(
          controller: controller,
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
          client: AiClient(
            transport: (_, __, ___) async {
              providerCalls++;
              throw StateError('Session lifecycle must not call a provider');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settleStorage(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (controller.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(controller.busy, isFalse);
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, String name) async {
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('assistant-session'))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('session-name')), name);
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('confirm-start-session'))),
    );
    await settleStorage(tester);
  }

  Future<void> addSeries(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      await repo.addExercise(controller.active!.id, name);
      final w = (await repo.load()).singleWhere((w) => w.isActive);
      await repo.addSet(w.exercises.single.id, '60', '13');
      await controller.refresh();
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'home start/finish preserves draft and cancellation, persists two sessions in one day',
    (tester) async {
      await openChat(tester);
      await tester.enterText(find.byType(TextField), 'Mi consulta pendiente');
      expect(find.text('Iniciar entreno'), findsOneWidget);

      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('assistant-session'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(controller.active, isNull);

      await start(tester, 'Gym · mañana');
      final firstId = controller.active!.id;
      expect(find.text('Finalizar entreno'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mi consulta pendiente',
      );
      await addSeries(tester, 'Chest Press');
      await tester.runAsync(() => repo.startRest(firstId, 90));
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('assistant-session'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fecha'), findsOneWidget);
      expect(find.text('Hora'), findsOneWidget);
      expect(find.text('8/10/2026'), findsOneWidget);
      expect(find.text('Cambiar hora'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(controller.active!.id, firstId);
      expect(await tester.runAsync(() => repo.loadRestTimer()), isNotNull);

      now = DateTime(2026, 10, 8, 9, 30);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('assistant-session'))),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('confirm-finish-session'))),
      );
      await settleStorage(tester);
      expect(controller.active, isNull);
      expect(controller.history.single.id, firstId);
      expect(controller.history.single.finishedAt, now);
      expect(await tester.runAsync(() => repo.loadRestTimer()), isNull);
      expect(find.text('Iniciar entreno'), findsOneWidget);

      now = DateTime(2026, 10, 8, 18);
      await start(tester, 'Gym · tarde');
      final secondId = controller.active!.id;
      expect(secondId, isNot(firstId));
      expect(controller.history.single.name, 'Gym · mañana');
      await addSeries(tester, 'Remo');
      now = DateTime(2026, 10, 8, 19);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('assistant-session'))),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('confirm-finish-session'))),
      );
      await settleStorage(tester);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(() async {
        await repo.close();
        await openRepository();
      });
      await openChat(tester);
      expect(controller.active, isNull);
      expect(controller.history, hasLength(2));
      expect(controller.history.map((w) => w.id).toSet(), {firstId, secondId});
      expect(controller.history.map((w) => w.startedAt.day).toSet(), {8});
      expect(controller.history.first.exercises.single.name, 'Remo');
      expect(controller.history.last.exercises.single.name, 'Chest Press');
      expect(find.text('Iniciar entreno'), findsOneWidget);
      expect(providerCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty session stays active; reopening restores finish button', (
    tester,
  ) async {
    await openChat(tester);
    await start(tester, 'Sin registros');
    final id = controller.active!.id;
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('assistant-session'))),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(const Key('confirm-finish-session'))),
    );
    await settleStorage(tester);
    expect(controller.active!.id, id);
    expect(controller.history, isEmpty);
    expect(find.textContaining('Registra al menos una serie'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(() async {
      await repo.close();
      await openRepository();
    });
    await openChat(tester);
    expect(controller.active!.id, id);
    expect(find.text('Finalizar entreno'), findsOneWidget);
    expect(providerCalls, 0);
  });

  testWidgets(
    'edited finish before a known series can be kept after explicit warning',
    (tester) async {
      await openChat(tester);
      await start(tester, 'Hora corregida');
      now = DateTime(2026, 10, 8, 11);
      await addSeries(tester, 'Chest Press');
      now = DateTime(2026, 10, 8, 17);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('assistant-session'))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('finish-time-value'))).data,
        '17:00',
      );
      await tester.tap(find.byKey(const Key('change-finish-time')));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, '10');
      await tester.enterText(fields.last, '00');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('finish-time-value'))).data,
        '10:00',
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('confirm-finish-session'))),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Hay una serie registrada'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Volver y corregir')));
      await tester.pumpAndSettle();
      expect(controller.active, isNotNull);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-finish-session')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('confirm-finish-session'))),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('accept-finish-time'))),
      );
      await settleStorage(tester);
      expect(controller.active, isNull);
      final saved = controller.history.single;
      expect(saved.finishedAt, DateTime(2026, 10, 8, 10));
      expect(saved.finishedRecordedAt, DateTime(2026, 10, 8, 17));
      expect(saved.finishTimeIssues, ['before_last_record']);
      expect(
        saved.exercises.single.sets.single.recordedAt,
        DateTime(2026, 10, 8, 11),
      );
      expect(providerCalls, 0);
    },
  );
}
