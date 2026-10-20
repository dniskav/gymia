import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/chat_archive_store.dart';
import 'package:gymia/domain/workout.dart';

class _FailCommit extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (key.contains('gymia.ai.chat.v1')) throw StateError('disk full');
    return super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  const store = ChatArchiveStore(profileId: 'local');
  final messages = [
    AiMessage(
      'user',
      'Original 👋',
      attachment: AiAttachment(
        name: 'photo.png',
        mime: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    ).forStorage(),
    const AiMessage('assistant', 'Respuesta original').forStorage(),
  ];
  final state = {
    'sessionId': 'old-session',
    'messages': messages,
    'pending': null,
  };
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      store.activeKey: jsonEncode(state),
    }),
  );

  test(
    'archive is complete, rotates session, retains original attachment and isolates accounts',
    () async {
      final next = await store.archive(
        state: state,
        transcript: messages,
        activityMessageIds: ['activity-message'],
        title: 'Prueba',
        summary: 'Resumen',
        reason: 'Fase cerrada',
        automatic: true,
      );
      expect(next['sessionId'], isNot('old-session'));
      expect(next['messages'], isEmpty);
      expect(next['archivedActivityMessageIds'], ['activity-message']);
      final id = ChatArchiveStore.index(next).single['id'] as String;
      final archived = await store.read(id);
      expect(archived['messages'], messages);
      expect(
        AiMessage.fromStorage(
          Map<String, dynamic>.from(
            (archived['messages'] as List).first as Map,
          ),
        ).attachment!.bytes,
        [1, 2, 3],
      );
      await expectLater(
        const ChatArchiveStore(profileId: 'other').read(id),
        throwsA(isA<ValidationException>()),
      );
      await expectLater(
        store.archive(
          state: state,
          transcript: messages,
          activityMessageIds: [],
          title: 'Stale',
          summary: '',
          reason: '',
          automatic: false,
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await store.active())!['messages'], isEmpty);
    },
  );

  test(
    'failed active/index commit retains active chat and never exposes an incomplete archive',
    () async {
      final failing = ChatArchiveStore(
        profileId: 'local',
        storage: _FailCommit(),
      );
      await expectLater(
        failing.archive(
          state: state,
          transcript: messages,
          activityMessageIds: [],
          title: 'Prueba',
          summary: '',
          reason: '',
          automatic: false,
        ),
        throwsStateError,
      );
      expect(jsonDecode((await storage.read(key: store.activeKey))!), state);
      expect(ChatArchiveStore.index(await store.active()), isEmpty);
    },
  );

  test(
    'bounded archive retrieval labels partial pages and retains full originals',
    () async {
      final rows = [
        for (var i = 0; i < 30; i++)
          AiMessage('user', 'Mensaje $i ${'x' * 1200}').forStorage(),
      ];
      final next = await store.archive(
        state: state,
        transcript: rows,
        activityMessageIds: [],
        title: 'Largo',
        summary: '',
        reason: '',
        automatic: false,
      );
      final id = ChatArchiveStore.index(next).single['id'] as String;
      final page = await store.excerpt(id);
      expect(page['hasMore'], isTrue);
      expect((page['messages'] as List).length, lessThanOrEqualTo(20));
      expect((await store.read(id))['messages'], rows);
      await expectLater(
        store.excerpt(id, start: -1),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  test('archive directives require complete, unique, bounded JSON', () {
    expect(
      chatDirective(
        '```gymia-archive\n{"title":"A","summary":"Continuar","reason":"Largo"}\n```',
        'archive',
      ),
      isNotNull,
    );
    expect(
      chatDirective(
        '```gymia-archive\n{"title":"A","summary":"Continuar"',
        'archive',
      ),
      isNull,
    );
    expect(
      chatDirective(
        '```gymia-archive\n{"title":"A","summary":"Continuar","reason":"Largo","delete":true}\n```',
        'archive',
      ),
      isNull,
    );
    expect(
      chatDirective('```gymia-recall\n{"id":"a","start":-1}\n```', 'recall'),
      isNull,
    );
  });
}
