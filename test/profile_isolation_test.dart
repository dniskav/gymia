import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:gymia/data/sqlite_workout_repository.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final profiles = ProfileStore.instance;
  const storage = FlutterSecureStorage();
  const a = UserProfile(subject: '111', email: 'a@example.test');
  const b = UserProfile(subject: '222', email: 'b@example.test');
  late UserProfile next;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall)? override;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await profiles.load();
    calls = [];
    next = a;
    override = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, (call) async {
          calls.add(call);
          if (override != null) return override!(call);
          return switch (call.method) {
            'connectIdentity' => next.toJson(),
            'authorize' => true,
            'disconnect' => null,
            _ => throw StateError('Unexpected ${call.method}'),
          };
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, null);
    FlutterSecureStorage.setMockInitialValues({});
    await profiles.load();
  });

  SheetContext sheet(String id) => SheetContext(
    id: id,
    name: 'Hoja $id',
    title: 'Registro',
    loadedAt: DateTime(2026),
    rows: [
      [id],
    ],
  );

  test(
    'local data remains unclaimed; two Google accounts retain separate sheets and secrets',
    () async {
      await const SheetContextStore().save(sheet('legacy'));
      await storage.write(key: 'gymia.ai.chat.v1', value: 'legacy chat');
      await profiles.connect();
      final aSheets = SheetContextStore(profileId: a.id);
      final aSettings = AiSettingsStore(profileId: a.id);
      expect(await aSheets.load(), isNull);
      expect(await aSettings.load(), isNull);
      await aSheets.save(sheet('a'));
      const config = AiConfig(
        service: AiService.custom,
        baseUrl: 'https://example.test/v1',
        model: 'test',
        protocol: AiProtocol.chatCompletions,
        apiKey: 'a-private-key',
      );
      await aSettings.save(config);
      await aSettings.markVerified(config);
      await storage.write(
        key: profileStorageKey('gymia.ai.chat.v1', a.id),
        value: 'a chat',
      );
      next = b;
      await profiles.connect();
      expect(profiles.activeId, b.id);
      expect(await SheetContextStore(profileId: b.id).load(), isNull);
      expect(await AiSettingsStore(profileId: b.id).load(), isNull);
      expect(
        await storage.read(key: profileStorageKey('gymia.ai.chat.v1', b.id)),
        isNull,
      );
      await SheetContextStore(profileId: b.id).save(sheet('b'));
      // A response captured in A can only save into A after switching to B.
      await aSheets.save(sheet('a-late'));
      expect((await SheetContextStore(profileId: b.id).load())!.id, 'b');
      next = a;
      await profiles.connect(expectedSubject: a.subject);
      expect((await aSheets.load())!.id, 'a-late');
      expect(await aSettings.isVerified(config), isTrue);
      await profiles.useLocal();
      expect((await const SheetContextStore().load())!.id, 'legacy');
      expect(await storage.read(key: 'gymia.ai.chat.v1'), 'legacy chat');
      expect(profiles.profiles.length, 2);
      final registry = jsonDecode(
        (await storage.read(key: ProfileStore.registryKey))!,
      );
      expect(registry.toString(), isNot(contains('a-private-key')));
    },
  );

  test(
    'cancel, mismatched account and corrupted identity cannot change selected profile',
    () async {
      await profiles.connect();
      next = b;
      await expectLater(
        profiles.connect(expectedSubject: a.subject),
        throwsFormatException,
      );
      expect(profiles.activeId, a.id);
      override = (_) async => throw PlatformException(code: 'GOOGLE_CANCELLED');
      await expectLater(profiles.connect(), throwsA(isA<PlatformException>()));
      expect(profiles.activeId, a.id);
      override = (_) async => {'subject': '../../unsafe', 'email': b.email};
      await expectLater(profiles.connect(), throwsFormatException);
      expect(profiles.activeId, a.id);
      await profiles.load();
      expect(profiles.activeId, a.id);
      expect(profiles.busy, isFalse);
    },
  );

  test(
    'authorization is bound to subject and a late result is rejected after switching',
    () async {
      await profiles.connect();
      await profiles.authorizeSheets(profileId: a.id);
      expect(calls.last.arguments, {
        'expectedSubject': a.subject,
        'email': a.email,
      });
      await expectLater(
        profiles.authorizeSheets(profileId: b.id),
        throwsFormatException,
      );
      final pending = Completer<Object?>();
      override = (call) async {
        if (call.method == 'authorize') return await pending.future;
        return b.toJson();
      };
      final request = profiles.authorizeSheets(profileId: a.id);
      final rejected = expectLater(request, throwsFormatException);
      await Future<void>.delayed(Duration.zero);
      await profiles.connect();
      pending.complete(true);
      await rejected;
      expect(profiles.activeId, b.id);
    },
  );

  test(
    'database isolation preserves legacy records across account database reopening',
    () async {
      final dir = await Directory.systemTemp.createTemp('gymia-profile-db-');
      final local = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/gymia.sqlite',
      );
      var account = await SqliteWorkoutRepository.open(
        factory: databaseFactoryFfi,
        path: '${dir.path}/gymia-${a.id}.sqlite',
      );
      try {
        final legacyId = await local.start('Histórico local');
        final id = await account.start('Cuenta A');
        await account.close();
        account = await SqliteWorkoutRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/gymia-${a.id}.sqlite',
        );
        expect((await account.load()).single.id, id);
        expect((await local.load()).single.id, legacyId);
        expect((await local.load()).single.name, 'Histórico local');
        final other = await SqliteWorkoutRepository.open(
          factory: databaseFactoryFfi,
          path: '${dir.path}/gymia-${b.id}.sqlite',
        );
        expect(await other.load(), isEmpty);
        await other.close();
      } finally {
        await local.close();
        await account.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
