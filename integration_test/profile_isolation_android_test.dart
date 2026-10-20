import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gymia/main.dart';
import 'package:gymia/data/profile_store.dart';
import 'package:gymia/data/sheet_context_store.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/user_profile.dart';
import 'package:gymia/ui/accounts.dart';
import 'package:gymia/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android profiles isolate SQLite, secure storage, UI and restart', (
    tester,
  ) async {
    // Controlled identity transport; real Android widgets, SQLite and encrypted
    // storage. Does not claim live OAuth validation with two Google accounts.
    const storage = FlutterSecureStorage();
    final profiles = ProfileStore.instance;
    final savedRegistry = await storage.read(key: ProfileStore.registryKey);
    final dir = await Directory.systemTemp.createTemp('gymia-profiles-qa-');
    const a = UserProfile(
      subject: 'qa_emulator_account_a',
      email: 'qa-a@example.test',
    );
    const b = UserProfile(
      subject: 'qa_emulator_account_b',
      email: 'qa-b@example.test',
    );
    var next = a;
    var cancelled = false;
    await storage.delete(key: ProfileStore.registryKey);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ProfileStore.channel, (call) async {
          if (call.method == 'disconnect') return null;
          if (call.method == 'connectIdentity') {
            if (cancelled) {
              throw PlatformException(
                code: 'GOOGLE_CANCELLED',
                message: 'Selección cancelada.',
              );
            }
            return next.toJson();
          }
          throw StateError('Unexpected ${call.method}');
        });
    Future<void> settle() async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(GymApp).evaluate().isNotEmpty &&
            tester.widget<GymApp>(find.byType(GymApp)).controller.profileId ==
                profiles.activeId) {
          break;
        }
      }
      await tester.pumpAndSettle();
    }

    Future<void> openAccounts() async {
      await tester.tap(find.byType(DrawerButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuenta y datos'));
      await tester.pumpAndSettle();
    }

    try {
      await tester.pumpWidget(Bootstrap(databaseDirectory: dir.path));
      await settle();
      final localController =
          tester.widget<GymApp>(find.byType(GymApp)).controller;
      await localController.run(
        () async =>
            localController.repository.start('Histórico que no se migra'),
      );
      final localId = localController.workouts.single.id;
      await tester.pumpAndSettle();
      await openAccounts();
      expect(find.text('Perfil local'), findsOneWidget);
      cancelled = true;
      await tester.tap(find.text('Conectar otra cuenta de Google'));
      await tester.pumpAndSettle();
      expect(find.text('Selección cancelada.'), findsOneWidget);
      expect(profiles.activeId, 'local');
      cancelled = false;
      await tester.tap(find.text('Conectar otra cuenta de Google'));
      await settle();
      expect(profiles.activeId, a.id);
      final aController = tester.widget<GymApp>(find.byType(GymApp)).controller;
      expect(aController.workouts, isEmpty);
      await aController.run(
        () async => aController.repository.start('Sesión de A'),
      );
      await SheetContextStore(profileId: a.id).save(
        SheetContext(
          id: 'qa-file-a',
          name: 'Hoja A',
          title: 'Registro',
          loadedAt: DateTime.now(),
          rows: [
            ['A'],
          ],
        ),
      );
      await storage.write(
        key: profileStorageKey('gymia.ai.chat.v1', a.id),
        value:
            '{"sessionId":"qa-a","messages":[{"role":"user","content":"Mensaje privado de A"}],"pending":null}',
      );
      next = b;
      await tester.pumpAndSettle();
      await openAccounts();
      await tester.tap(find.text('Conectar otra cuenta de Google'));
      await settle();
      expect(profiles.activeId, b.id);
      final bController = tester.widget<GymApp>(find.byType(GymApp)).controller;
      expect(bController.workouts, isEmpty);
      expect(find.textContaining('Mensaje privado de A'), findsNothing);
      expect(await SheetContextStore(profileId: b.id).load(), isNull);
      await bController.run(
        () async => bController.repository.start('Sesión de B'),
      );
      // Recreate the production bootstrap to exercise persisted selection.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await localController.repository.close();
        await aController.repository.close();
        await bController.repository.close();
      });
      await tester.pumpWidget(Bootstrap(databaseDirectory: dir.path));
      await settle();
      expect(profiles.activeId, b.id);
      expect(
        tester
            .widget<GymApp>(find.byType(GymApp))
            .controller
            .workouts
            .single
            .name,
        'Sesión de B',
      );
      next = a;
      await openAccounts();
      await tester.tap(find.text(a.email));
      await settle();
      expect(profiles.activeId, a.id);
      expect(
        tester
            .widget<GymApp>(find.byType(GymApp))
            .controller
            .workouts
            .single
            .name,
        'Sesión de A',
      );
      expect(
        (await SheetContextStore(profileId: a.id).load())!.id,
        'qa-file-a',
      );
      await openAccounts();
      await tester.ensureVisible(
        find.text('Desconectar y volver al perfil local'),
      );
      await tester.tap(find.text('Desconectar y volver al perfil local'));
      await settle();
      expect(profiles.activeId, 'local');
      expect(
        tester
            .widget<GymApp>(find.byType(GymApp))
            .controller
            .workouts
            .single
            .id,
        localId,
      );
      expect(find.byType(AccountsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ProfileStore.channel, null);
      for (final profile in [a, b]) {
        for (final key in ['gymia.sheet.context.v1', 'gymia.ai.chat.v1']) {
          await storage.delete(key: profileStorageKey(key, profile.id));
        }
      }
      if (savedRegistry == null) {
        await storage.delete(key: ProfileStore.registryKey);
      } else {
        await storage.write(
          key: ProfileStore.registryKey,
          value: savedRegistry,
        );
      }
      await profiles.load();
      await dir.delete(recursive: true);
    }
  });

  testWidgets(
    'native bridge rejects missing and mismatched account authorization',
    (tester) async {
      // No mock here: these calls reach GoogleSheetsBridge.kt on Android.
      const channel = ProfileStore.channel;
      await channel.invokeMethod<void>('disconnect');
      await expectLater(
        channel.invokeMethod<bool>('authorize'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'GOOGLE_PROFILE_REQUIRED',
          ),
        ),
      );
      for (final method in ['list', 'tabs', 'read']) {
        await expectLater(
          channel.invokeMethod<Object>(method, {
            'expectedSubject': 'unverified-other-account',
            'id': 'untrusted-file',
            'title': 'Registro',
          }),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'GOOGLE_ACCOUNT_MISMATCH',
            ),
          ),
        );
      }
    },
  );
}
