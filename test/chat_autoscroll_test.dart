import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/activity.dart';
import 'package:gymia/ui/assistant_chat.dart';
import 'package:gymia/ui/chat_message.dart';

class StreamingTestClient extends AiClient {
  final answer = Completer<String>();
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
    return answer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('follows restored chat, large stream chunks and keyboard resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    FlutterSecureStorage.setMockInitialValues({
      'gymia.ai.chat.v1': jsonEncode({
        'sessionId': 'scroll-test',
        'messages': [
          for (var i = 0; i < 90; i++)
            AiMessage(
              'assistant',
              'Mensaje anterior $i\n${List.filled(1 + i % 12, 'Detalle del ejercicio con altura variable.').join('\n')}',
            ).forStorage(),
        ],
      }),
    });
    const config = AiConfig(
      service: AiService.custom,
      protocol: AiProtocol.chatCompletions,
      baseUrl: 'https://example.test/v1',
      model: 'test-model',
      apiKey: 'test-key',
    );
    await tester.runAsync(() async {
      await const AiSettingsStore().save(config);
      await const AiSettingsStore().markVerified(config);
    });
    final dir =
        (await tester.runAsync(
          () => Directory.systemTemp.createTemp('gymia-scroll-'),
        ))!;
    final repo =
        (await tester.runAsync(
          () => SqliteWorkoutRepository.open(
            factory: databaseFactoryFfi,
            path: '${dir.path}/test.sqlite',
          ),
        ))!;
    final controller = WorkoutController(repo);
    await tester.runAsync(controller.refresh);
    final client = StreamingTestClient();
    final availability = AiAvailability(
      catalog: AiModelCatalog(
        transport:
            (_, __) async => {
              'data': [
                {'id': 'test-model'},
              ],
            },
      ),
    );
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
    final list = find.byKey(const Key('assistant-transcript'));
    final scroll = tester.widget<ListView>(list).controller!;
    void expectEnd() {
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.position.extentAfter, lessThan(1));
    }

    expectEnd();

    // Reading older messages must remain possible until new content arrives.
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(120));
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'Empezamos',
    );
    await tester.tap(find.byTooltip('Enviar'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    Future<void> settleScroll() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await settleScroll();
    expect(client.emit, isNotNull);
    expectEnd();

    await tester.drag(list, const Offset(0, 600));
    await settleScroll();
    final partial = List.filled(
      30,
      'Texto progresivo del entrenamiento.',
    ).join('\n\n');
    final readingPosition = scroll.position.pixels;
    client.emit!(partial);
    await settleScroll();
    expect(scroll.position.extentAfter, greaterThan(120));
    expect(scroll.position.pixels, closeTo(readingPosition, 1));
    expect(find.byKey(const Key('chat-latest')), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settleScroll();
    expect(scroll.position.extentAfter, greaterThan(120));
    expect(find.byKey(const Key('activity-start-stop')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('assistant-composer'))).bottom,
      lessThanOrEqualTo(500),
    );

    client.answer.complete('$partial\n\nFinal de la respuesta.');
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(120));
    await tester.tap(find.byKey(const Key('chat-latest')));
    await tester.pumpAndSettle();
    expectEnd();
    expect(find.text('Esperando al modelo…'), findsNothing);
    // Local activity confirmations do not pass through receiveText(). They
    // must bring the newest message into view even after reading history.
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await repo.prepareActivity(ActivityDefinition(name: 'Prueba de scroll'));
      await controller.refresh();
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await repo.recordActivityMessage(
        controller.focus!.id,
        'Confirmación local al final del chat.',
        role: 'assistant',
      );
      await controller.refresh();
    });
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(120));
    await tester.tap(find.byKey(const Key('chat-latest')));
    await tester.pumpAndSettle();
    expectEnd();
    final latest = find.byWidgetPredicate(
      (widget) =>
          widget is ChatMessageBody &&
          widget.text == 'Confirmación local al final del chat.',
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

    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await repo.cancelActivityPreparation(controller.focus!.id);
      await controller.refresh();
    });
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    availability.dispose();
    controller.dispose();
    await tester.runAsync(repo.close);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
