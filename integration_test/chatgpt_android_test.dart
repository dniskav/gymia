import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jose/jose.dart';
import 'package:gymia/data/chatgpt_auth.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/ui/ai_settings.dart';
import 'package:gymia/ui/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android loopback OAuth verifies identity, stores securely, uses plan and disconnects',
    (tester) async {
      const profile = 'qa-chatgpt-android';
      const accountKey = 'gymia.chatgpt.accounts.v1.profile.$profile';
      const storage = FlutterSecureStorage();
      await storage.delete(key: accountKey);
      await const AiSettingsStore(profileId: profile).delete();
      final signingKey = JsonWebKey.generate('RS256', keyBitLength: 2048);
      late Uri authorize;
      var browserReturns = 0, inferenceCalls = 0, planGranted = false;
      final auth = ChatGptAuth(
        profileId: profile,
        browser: (uri) async {
          authorize = uri;
          browserReturns++;
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          try {
            final response =
                await (await client.getUrl(
                  redirect.replace(
                    queryParameters: {
                      'state': uri.queryParameters['state']!,
                      'code': 'qa-code',
                      'client_id': 'oaiapp_android',
                    },
                  ),
                )).close();
            if (response.statusCode != 200) {
              throw StateError('Loopback failed');
            }
            await response.drain<void>();
          } finally {
            client.close(force: true);
          }
        },
        transport: (uri, form) async {
          if (uri.path.contains('openid-configuration')) {
            return const ChatGptHttpResult(200, {
              'issuer': ChatGptAuth.issuer,
              'jwks_uri': 'https://auth.openai.com/.well-known/jwks.json',
              'revocation_endpoint':
                  'https://auth.openai.com/api/accounts/oauth/revoke',
            });
          }
          if (uri.path.contains('jwks')) {
            return ChatGptHttpResult(200, {
              'keys': [
                JsonWebKey.fromCryptoKeys(
                  publicKey: signingKey.cryptoKeyPair.publicKey,
                ).toJson(),
              ],
            });
          }
          if (uri.path.endsWith('/revoke')) {
            return const ChatGptHttpResult(200, {});
          }
          planGranted = authorize.queryParameters['scope']!.contains(
            'chatgpt.tokens.use.direct',
          );
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final token =
              (JsonWebSignatureBuilder()
                    ..jsonContent = {
                      'iss': ChatGptAuth.issuer,
                      'sub': 'android-fixture',
                      'email': 'qa@example.test',
                      'aud': 'oaiapp_android',
                      'exp': now + 3600,
                      'iat': now,
                      'nonce': authorize.queryParameters['nonce'],
                    }
                    ..addRecipient(signingKey, algorithm: 'RS256'))
                  .build()
                  .toCompactSerialization();
          return ChatGptHttpResult(200, {
            'access_token': 'qa-token',
            'refresh_token': 'qa-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope':
                planGranted
                    ? ChatGptAuth.planScopes
                    : ChatGptAuth.identityScopes,
            'id_token': token,
          });
        },
      );
      final catalog = AiModelCatalog(
        chatGptAuth: auth,
        transport: (_, headers) async {
          if (headers['Authorization'] != 'Bearer qa-token') {
            throw StateError('Bearer missing');
          }
          return {
            'models': [
              {
                'slug': 'qa-model',
                'display_name': 'Modelo de prueba',
                'visibility': 'list',
              },
            ],
          };
        },
      );
      final client = AiClient(
        chatGptAuth: auth,
        transport: (uri, headers, body) async {
          if (uri.toString() != 'https://api.openai.com/v1/responses' ||
              body['stream'] != true ||
              body['store'] != false) {
            throw StateError('Wrong plan contract');
          }
          inferenceCalls++;
          return {
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'Conexión Android comprobada',
                  },
                ],
              },
            ],
          };
        },
      );
      Future<void> until(Finder finder) async {
        for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pump(const Duration(milliseconds: 150));
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: gymTheme,
            home: AiSettingsScreen(
              profileId: profile,
              chatGptAuth: auth,
              catalog: catalog,
              client: client,
            ),
          ),
        );
        final provider = find.byType(DropdownButtonFormField<AiService>);
        await until(provider);
        for (
          var i = 0;
          i < 100 &&
              tester
                      .widget<DropdownButtonFormField<AiService>>(provider)
                      .onChanged ==
                  null;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(provider);
        await tester.pumpAndSettle();
        await tester.tap(find.text('ChatGPT · usar mi plan').last);
        await tester.pumpAndSettle();
        await tap(find.byKey(const Key('chatgpt-connect')));
        await until(find.text('Conectada · solo identidad'));
        expect(planGranted, false);
        await tap(find.byKey(const Key('chatgpt-enable-plan')));
        await until(find.text('Conectada · permiso de uso del plan concedido'));
        await until(
          find.textContaining('Modelos disponibles para esta cuenta: 1'),
        );
        await tap(find.text('Probar conexión · usa mi plan ChatGPT'));
        await until(find.textContaining('El proveedor respondió:'));
        expect(inferenceCalls, 1);
        expect(browserReturns, 2);
        if (const bool.fromEnvironment('GYMIA_VISUAL_QA')) {
          await tester.scrollUntilVisible(
            find.byKey(const Key('chatgpt-connect')),
            -180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          // ignore: avoid_print
          print('GYMIA_CHATGPT_SETTINGS_PREVIEW');
          await Future<void>.delayed(const Duration(seconds: 8));
        }
        final saved = await const AiSettingsStore(profileId: profile).load();
        expect(saved!.usesChatGpt, true);
        expect(saved.apiKey, isEmpty);
        final restarted = ChatGptAuth(profileId: profile);
        expect((await restarted.account('oaiapp_android')).canUsePlan, true);
        expect(await ChatGptAuth(profileId: 'qa-other').accounts(), isEmpty);
        await tap(find.byKey(const Key('chatgpt-disconnect')));
        await until(find.textContaining('Sesión ChatGPT desconectada.'));
        expect((await restarted.account('oaiapp_android')).connected, false);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('QA OAuth Android completada')),
          ),
        );
      } finally {
        await auth.cancel();
        await storage.delete(key: accountKey);
        await const AiSettingsStore(profileId: profile).delete();
      }
    },
  );
  testWidgets(
    'Android opens the official authorization in the system browser and returns after cancellation',
    (tester) async {
      // No user credentials are entered. This checks browser launch, not live admission.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Comprobando navegador de ChatGPT')),
        ),
      );
      final auth = ChatGptAuth(
        profileId: 'qa-browser-probe',
        timeout: const Duration(seconds: 20),
      );
      final pending = auth.connect();
      final assertion = expectLater(pending, throwsA(isA<ChatGptFailure>()));
      // Leave the official page visible briefly for manual/emulator inspection.
      await Future<void>.delayed(const Duration(seconds: 8));
      // ignore: avoid_print
      print('GYMIA_CHATGPT_BROWSER_PREVIEW');
      await Future<void>.delayed(const Duration(seconds: 6));
      await auth.cancel();
      await assertion;
      expect(await auth.accounts(), isEmpty);
    },
  );
}
