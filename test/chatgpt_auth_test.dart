import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jose/jose.dart';
import 'package:gymia/data/chatgpt_auth.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/data/ai_stream_response.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/workout.dart';

class _LoopbackClient implements HttpClient {
  _LoopbackClient(this.client, this.uri);
  final HttpClient client;
  final Uri uri;
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => client.postUrl(uri);
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JsonWebKey key;
  setUpAll(() {
    key = JsonWebKey.generate('RS256', keyBitLength: 2048);
  });
  setUp(() {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
  });

  String sign(Map<String, dynamic> extra, {JsonWebKey? signingKey}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (JsonWebSignatureBuilder()
          ..jsonContent = {
            'iss': ChatGptAuth.issuer,
            'sub': 'person-a',
            'email': 'person@example.test',
            'aud': 'oaiapp_test',
            'exp': now + 3600,
            'iat': now,
            ...extra,
          }
          ..addRecipient(signingKey ?? key, algorithm: 'RS256'))
        .build()
        .toCompactSerialization();
  }

  ChatGptTransport identityTransport({
    Map<String, dynamic>? token,
    void Function(Map<String, String>)? formSeen,
  }) => (uri, form) async {
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
            publicKey: key.cryptoKeyPair.publicKey,
          ).toJson(),
        ],
      });
    }
    formSeen?.call(form!);
    return ChatGptHttpResult(200, token ?? {});
  };
  Future<void> callback(Uri authorization, {Map<String, String>? extra}) async {
    final params = authorization.queryParameters;
    final uri = Uri.parse(params['redirect_uri']!).replace(
      queryParameters: {
        'state': params['state']!,
        'code': 'fixture-code',
        'client_id': 'oaiapp_test',
        ...?(extra),
      },
    );
    final http = HttpClient();
    try {
      final r = await (await http.getUrl(uri)).close();
      await r.drain<void>();
    } finally {
      http.close(force: true);
    }
  }

  Future<ChatGptAuth> seed({
    String profile = 'local',
    String id = 'oaiapp_test',
    bool expired = false,
    String? scopes,
  }) async {
    await ChatGptAuth.storage.write(
      key:
          profile == 'local'
              ? 'gymia.chatgpt.accounts.v1'
              : 'gymia.chatgpt.accounts.v1.profile.$profile',
      value: jsonEncode({
        id: {
          'client_id': id,
          'subject': 'person-a',
          'email': 'person@example.test',
          'issuer': ChatGptAuth.issuer,
          'access_token': 'fixture-access',
          'refresh_token': 'fixture-refresh',
          'id_token': 'fixture-id',
          'scopes': (scopes ?? ChatGptAuth.planScopes).split(' '),
          'expires_at':
              DateTime.now()
                  .add(Duration(hours: expired ? -1 : 1))
                  .toIso8601String(),
        },
      }),
    );
    return ChatGptAuth(profileId: profile, timeout: const Duration(seconds: 3));
  }

  AiConfig config({
    String profile = 'local',
    String base = 'https://api.openai.com/v1',
  }) => AiConfig(
    service: AiService.chatgpt,
    baseUrl: base,
    model: 'catalog-model',
    protocol: AiProtocol.responses,
    apiKey: '',
    chatGptClientId: 'oaiapp_test',
    profileId: profile,
  );

  test('PKCE uses RFC7636 S256 test vector', () {
    expect(
      ChatGptAuth.challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });
  test(
    'callback rejects wrong state, duplicate parameters and wrong path before valid return',
    () async {
      final server = await ChatGptCallback.open('correct');
      final http = HttpClient();
      try {
        for (final suffix in [
          '/auth/callback?state=wrong',
          '/other?state=correct',
          '/auth/callback?state=correct&state=correct',
        ]) {
          final response =
              await (await http.getUrl(
                Uri.parse('http://127.0.0.1:${server.server.port}$suffix'),
              )).close();
          expect(response.statusCode, 400);
          await response.drain<void>();
          expect(server.completer.isCompleted, false);
        }
        final r =
            await (await http.getUrl(
              server.uri.replace(
                queryParameters: {'state': 'correct', 'code': 'ok'},
              ),
            )).close();
        expect(r.statusCode, 200);
        await r.drain<void>();
        expect((await server.wait(const Duration(seconds: 1)))['code'], 'ok');
        final replay =
            await (await http.getUrl(
              server.uri.replace(queryParameters: {'state': 'correct'}),
            )).close();
        expect(replay.statusCode, 400);
        await replay.drain<void>();
      } finally {
        http.close(force: true);
        await server.close();
      }
    },
  );
  test(
    'new registration exchanges issued ID and exact redirect, verifies JWKS and saves only granted identity',
    () async {
      late Uri opened;
      late Map<String, String> exchange;
      final auth = ChatGptAuth(
        profileId: 'local',
        timeout: const Duration(seconds: 3),
        browser: (uri) async {
          opened = uri;
          await callback(uri);
        },
        transport: (uri, form) async {
          if (form != null) {
            exchange = form;
            return ChatGptHttpResult(200, {
              'access_token': 'fixture-access',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': sign({'nonce': opened.queryParameters['nonce']}),
              'scope': ChatGptAuth.identityScopes,
            });
          }
          return identityTransport()(uri, form);
        },
      );
      final account = await auth.connect();
      expect(opened.host, 'auth.openai.com');
      expect(opened.queryParameters['client_id'], 'dynamic_agent_client');
      expect(opened.queryParameters['scope'], ChatGptAuth.identityScopes);
      expect(exchange['client_id'], 'oaiapp_test');
      expect(exchange['redirect_uri'], opened.queryParameters['redirect_uri']);
      expect(
        ChatGptAuth.challenge(exchange['code_verifier']!),
        opened.queryParameters['code_challenge'],
      );
      expect(account.subject, 'person-a');
      expect(account.canUsePlan, false);
      expect((await auth.accounts()).single.clientId, 'oaiapp_test');
      await expectLater(
        auth.authorized('oaiapp_test', (_) async => 'no'),
        throwsA(isA<ChatGptFailure>().having((e) => e.code, 'code', 'no_plan')),
      );
    },
  );
  test(
    'returning account reuses issued ID and host and explicitly enables plan',
    () async {
      await seed();
      late Uri opened;
      final auth = ChatGptAuth(
        profileId: 'local',
        timeout: const Duration(seconds: 3),
        browser: (uri) async {
          opened = uri;
          await callback(uri);
        },
        transport: (uri, form) async {
          if (form != null) {
            return ChatGptHttpResult(200, {
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': sign({'nonce': opened.queryParameters['nonce']}),
              'scope': ChatGptAuth.planScopes,
            });
          }
          return identityTransport()(uri, form);
        },
      );
      expect(
        (await auth.connect(
          clientId: 'oaiapp_test',
          usePlan: true,
          consent: true,
        )).canUsePlan,
        true,
      );
      expect(opened.queryParameters['client_id'], 'oaiapp_test');
      expect(opened.queryParameters.containsKey('agent_name_hint'), false);
      expect(opened.queryParameters['prompt'], 'consent');
      expect(opened.queryParameters['id_token_hint'], 'fixture-id');
      final host = opened.queryParameters['ext_agent_host_id'];
      await auth.connect(clientId: 'oaiapp_test', usePlan: true);
      expect(opened.queryParameters['ext_agent_host_id'], host);
      expect(opened.queryParameters.containsKey('prompt'), false);
    },
  );
  test(
    'same email in different workspace registrations keeps separate credentials',
    () async {
      var issued = 'oaiapp_test';
      late Uri opened;
      final auth = ChatGptAuth(
        profileId: 'local',
        browser: (uri) async {
          opened = uri;
          await callback(uri, extra: {'client_id': issued});
        },
        transport: (uri, form) async {
          if (form != null) {
            return ChatGptHttpResult(200, {
              'access_token': 'access-$issued',
              'refresh_token': 'refresh-$issued',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': sign({
                'aud': issued,
                'nonce': opened.queryParameters['nonce'],
              }),
              'scope': ChatGptAuth.planScopes,
            });
          }
          return identityTransport()(uri, form);
        },
      );
      await auth.connect(usePlan: true);
      issued = 'oaiapp_workspace_b';
      await auth.connect(usePlan: true);
      expect((await auth.accounts()).length, 2);
      expect(
        await auth.authorized('oaiapp_test', (t) async => t),
        'access-oaiapp_test',
      );
      expect(
        await auth.authorized('oaiapp_workspace_b', (t) async => t),
        'access-oaiapp_workspace_b',
      );
    },
  );
  test(
    'code exchange failure retains the issued registration ID for a fresh PKCE attempt',
    () async {
      var attempts = 0;
      late Uri opened;
      final auth = ChatGptAuth(
        profileId: 'local',
        browser: (uri) async {
          opened = uri;
          await callback(uri);
        },
        transport: (uri, form) async {
          if (form != null) {
            attempts++;
            if (attempts == 1) {
              return const ChatGptHttpResult(400, {'error': 'invalid_grant'});
            }
            return ChatGptHttpResult(200, {
              'access_token': 'fixture-access',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': sign({'nonce': opened.queryParameters['nonce']}),
              'scope': ChatGptAuth.identityScopes,
            });
          }
          return identityTransport()(uri, form);
        },
      );
      await expectLater(auth.connect(), throwsA(isA<ChatGptFailure>()));
      expect(await auth.accounts(), isEmpty);
      final firstState = opened.queryParameters['state'];
      await auth.connect();
      expect(opened.queryParameters['client_id'], 'oaiapp_test');
      expect(opened.queryParameters['state'], isNot(firstState));
      expect(opened.queryParameters.containsKey('agent_name_hint'), false);
    },
  );
  test(
    'signature, nonce, audience, issuer, expiry and account substitution fail closed',
    () async {
      final auth = ChatGptAuth(
        profileId: 'local',
        transport: identityTransport(),
      );
      for (final claims in <Map<String, dynamic>>[
        {'nonce': 'other'},
        {'aud': 'other'},
        {'iss': 'https://attacker.test'},
        {'exp': 0},
        {'sub': ''},
        {
          'aud': ['oaiapp_test', 'other'],
        },
      ]) {
        await expectLater(
          auth.verifyIdentity(
            sign({'nonce': 'expected', ...claims}),
            'oaiapp_test',
            nonce: 'expected',
          ),
          throwsA(isA<ChatGptFailure>()),
        );
      }
      final attacker = JsonWebKey.generate('RS256', keyBitLength: 2048);
      await expectLater(
        auth.verifyIdentity(
          sign({'nonce': 'expected'}, signingKey: attacker),
          'oaiapp_test',
          nonce: 'expected',
        ),
        throwsA(isA<ChatGptFailure>()),
      );
      await seed();
      late Uri opened;
      final changed = ChatGptAuth(
        profileId: 'local',
        timeout: const Duration(seconds: 3),
        browser: (uri) async {
          opened = uri;
          await callback(uri);
        },
        transport: (uri, form) async {
          if (form != null) {
            return ChatGptHttpResult(200, {
              'access_token': 'other',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': sign({
                'nonce': opened.queryParameters['nonce'],
                'sub': 'person-b',
              }),
              'scope': ChatGptAuth.planScopes,
            });
          }
          return identityTransport()(uri, form);
        },
      );
      await expectLater(
        changed.connect(clientId: 'oaiapp_test'),
        throwsA(isA<ChatGptFailure>()),
      );
      expect((await changed.account('oaiapp_test')).subject, 'person-a');
    },
  );
  test('cancel and access denial do not create registrations', () async {
    late ChatGptAuth auth;
    auth = ChatGptAuth(
      profileId: 'local',
      timeout: const Duration(seconds: 3),
      browser: (_) async {
        await auth.cancel();
      },
    );
    await expectLater(
      auth.connect(),
      throwsA(isA<ChatGptFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(await auth.accounts(), isEmpty);
    final denied = ChatGptAuth(
      profileId: 'local',
      timeout: const Duration(seconds: 3),
      browser: (uri) async {
        await callback(uri, extra: {'error': 'access_denied'});
      },
    );
    await expectLater(
      denied.connect(),
      throwsA(
        isA<ChatGptFailure>().having((e) => e.code, 'code', 'access_denied'),
      ),
    );
  });
  test(
    'timeout closes the callback and a changed issued client never replaces saved credentials',
    () async {
      late Uri opened;
      final timed = ChatGptAuth(
        profileId: 'timeout',
        timeout: const Duration(milliseconds: 30),
        browser: (uri) async {
          opened = uri;
        },
      );
      await expectLater(
        timed.connect(),
        throwsA(
          isA<ChatGptFailure>().having(
            (e) => e.code,
            'code',
            'callback_timeout',
          ),
        ),
      );
      final client = HttpClient();
      try {
        await expectLater(
          client.getUrl(Uri.parse(opened.queryParameters['redirect_uri']!)),
          throwsA(isA<SocketException>()),
        );
      } finally {
        client.close(force: true);
      }
      await seed();
      final changed = ChatGptAuth(
        profileId: 'local',
        browser: (uri) async {
          await callback(uri, extra: {'client_id': 'oaiapp_other'});
        },
        transport: (_, __) async {
          throw StateError('Must not exchange changed client');
        },
      );
      await expectLater(
        changed.connect(clientId: 'oaiapp_test'),
        throwsA(isA<ChatGptFailure>()),
      );
      expect(
        (await changed.account('oaiapp_test')).data['access_token'],
        'fixture-access',
      );
    },
  );
  test(
    'parallel expired-token calls rotate once, save replacement and retain registration after revocation',
    () async {
      await seed(expired: true);
      var refreshes = 0;
      final auth = ChatGptAuth(
        profileId: 'local',
        transport: (uri, form) async {
          if (form?['grant_type'] == 'refresh_token') {
            refreshes++;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(form!['client_id'], 'oaiapp_test');
            expect(form.containsKey('scope'), false);
            return const ChatGptHttpResult(200, {
              'access_token': 'rotated-access',
              'refresh_token': 'rotated-refresh',
              'token_type': 'Bearer',
              'expires_in': 3600,
            });
          }
          if (form?['token_type_hint'] == 'refresh_token') {
            expect(form!['token'], 'rotated-refresh');
            return const ChatGptHttpResult(200, {});
          }
          return identityTransport()(uri, form);
        },
      );
      final results = await Future.wait(
        List.generate(4, (_) => auth.authorized('oaiapp_test', (t) async => t)),
      );
      expect(results, everyElement('rotated-access'));
      expect(refreshes, 1);
      expect(await auth.disconnect('oaiapp_test'), true);
      final record = (await auth.accounts()).single;
      expect(record.connected, false);
      expect(record.data.containsKey('id_token'), false);
    },
  );
  test(
    'one rejected bearer refreshes once without OAuth browser; disconnect invalidates an in-flight answer',
    () async {
      await seed();
      var refreshes = 0, calls = 0;
      final auth = ChatGptAuth(
        profileId: 'local',
        timeout: const Duration(seconds: 3),
        browser: (_) async {
          fail('No browser on renewal');
        },
        transport: (uri, form) async {
          refreshes++;
          return const ChatGptHttpResult(200, {
            'access_token': 'new-token',
            'refresh_token': 'new-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
          });
        },
      );
      final result = await auth.authorized('oaiapp_test', (token) async {
        calls++;
        if (calls == 1) {
          throw const ChatGptFailure('request_failed', status: 401);
        }
        return token;
      });
      expect(result, 'new-token');
      expect(calls, 2);
      expect(refreshes, 1);
      final started = Completer<void>(), release = Completer<void>();
      final pending = auth.authorized('oaiapp_test', (token) async {
        started.complete();
        await release.future;
        return 'late answer';
      });
      final assertion = expectLater(
        pending,
        throwsA(
          isA<ChatGptFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await started.future;
      await auth.disconnect('oaiapp_test');
      release.complete();
      await assertion;
    },
  );
  test(
    'terminal refresh erases tokens, transient failure preserves them and profile cannot borrow credentials',
    () async {
      await seed(expired: true);
      final transient = ChatGptAuth(
        profileId: 'local',
        transport: (_, __) async => const ChatGptHttpResult(503, {}),
      );
      await expectLater(
        transient.authorized('oaiapp_test', (_) async => ''),
        throwsA(isA<ChatGptFailure>()),
      );
      expect((await transient.account('oaiapp_test')).connected, true);
      final terminal = ChatGptAuth(
        profileId: 'local',
        transport:
            (_, __) async =>
                const ChatGptHttpResult(400, {'error': 'invalid_grant'}),
      );
      await expectLater(
        terminal.authorized('oaiapp_test', (_) async => ''),
        throwsA(isA<ChatGptFailure>()),
      );
      expect((await terminal.account('oaiapp_test')).connected, false);
      expect(
        await ChatGptAuth(profileId: 'another-profile').accounts(),
        isEmpty,
      );
      await expectLater(
        const AiSettingsStore(profileId: 'another-profile').save(config()),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test(
    'provider confines OAuth to OpenAI, forces streaming without callback and stores no tokens in config',
    () async {
      final auth = await seed();
      final client = AiClient(
        chatGptAuth: auth,
        transport: (uri, headers, body) async {
          expect(uri.toString(), 'https://api.openai.com/v1/responses');
          expect(headers['Authorization'], 'Bearer fixture-access');
          expect(body['stream'], true);
          expect(body['store'], false);
          expect(body.containsKey('previous_response_id'), false);
          return {
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'Respuesta'},
                ],
              },
            ],
          };
        },
      );
      expect(
        await client.reply(
          config(),
          [const AiMessage('user', 'Hola')],
          system: 'Contexto',
          sessionId: 'test',
        ),
        'Respuesta',
      );
      expect(jsonEncode(config().toJson()), isNot(contains('fixture-access')));
      expect(
        () => config(base: 'https://attacker.test/v1').validate(),
        throwsA(isA<ValidationException>()),
      );
      final catalog = AiModelCatalog(
        chatGptAuth: auth,
        transport:
            (uri, headers) async => {
              'models': [
                {
                  'slug': 'first',
                  'display_name': 'Primero',
                  'visibility': 'list',
                },
                {'slug': 'hidden', 'visibility': 'hidden'},
                {'slug': 'second', 'visibility': 'list'},
              ],
            },
      );
      expect((await catalog.list(config())).map((m) => m.id), [
        'first',
        'second',
      ]);
    },
  );
  test(
    'real Responses HTTP requires terminal completion even without an onText consumer',
    () async {
      for (final terminal in ['completed', 'failed', 'truncated']) {
        final auth = await seed();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final direct = HttpClient();
        final received = server.first.then((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['stream'], true);
          expect(body['store'], false);
          expect(
            request.headers.value('authorization'),
            'Bearer fixture-access',
          );
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'Plan de prueba'})}\n\n',
          );
          if (terminal == 'completed') {
            request.response.write(
              'data: ${jsonEncode({
                'type': 'response.completed',
                'response': {'status': 'completed'},
              })}\n\n',
            );
          } else if (terminal == 'failed') {
            request.response.write(
              'data: ${jsonEncode({
                'type': 'response.failed',
                'response': {
                  'error': {'code': 'subscription_sharing_usage_limit_exceeded'},
                },
              })}\n\n',
            );
          }
          await request.response.close();
        });
        try {
          final call = HttpOverrides.runZoned(
            () => AiClient(chatGptAuth: auth).reply(
              config(),
              [const AiMessage('user', 'Planifica')],
              system: 'Contexto',
              sessionId: 'qa',
            ),
            createHttpClient:
                (_) => _LoopbackClient(
                  direct,
                  Uri.parse('http://127.0.0.1:${server.port}/responses'),
                ),
          );
          if (terminal == 'completed') {
            expect(await call, 'Plan de prueba');
          } else {
            await expectLater(call, throwsA(isA<ValidationException>()));
          }
          await received;
        } finally {
          direct.close(force: true);
          await server.close(force: true);
        }
      }
    },
  );
  test('stream usage failure is actionable and never a completed response', () {
    final stream = AiStreamResponse(AiProtocol.responses, chatGpt: true);
    stream.add({
      'type': 'response.output_text.delta',
      'delta': 'partial action',
    });
    expect(
      () => stream.add({
        'type': 'response.failed',
        'response': {
          'error': {'code': 'subscription_sharing_usage_limit_exceeded'},
        },
      }),
      throwsA(
        isA<ChatGptFailure>().having(
          (e) => e.message,
          'message',
          contains('límite'),
        ),
      ),
    );
    expect(stream.complete, false);
    expect(() => stream.response(), throwsA(isA<ValidationException>()));
    final detail = ChatGptFailure.response(403, {
      'detail': 'diagnostic not shown',
    }, requestId: 'request-id');
    expect(detail.shape, 'detail');
    expect(detail.requestId, 'request-id');
    expect(detail.toString(), isNot(contains('diagnostic not shown')));
  });
}
