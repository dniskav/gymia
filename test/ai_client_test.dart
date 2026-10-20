import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/workout.dart';
import 'package:gymia/data/ai_client.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:async';

AiConfig config(
  AiProtocol protocol, {
  AiService service = AiService.opencodeGo,
  String? base,
}) => AiConfig(
  service: service,
  baseUrl: base ?? service.baseUrl,
  model: 'test-model',
  protocol: protocol,
  apiKey: 'test-secret',
);

// Exercise the production HTTP implementation against a local server while
// retaining HTTPS validation for the configured provider. No live API calls.
class _LoopbackHttpClient implements HttpClient {
  _LoopbackHttpClient(this.delegate, this.destination);
  final HttpClient delegate;
  final Uri destination;

  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => delegate.postUrl(destination);
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'real HTTP stream publishes UTF-8 text before completion and rejects truncation',
    () async {
      for (final truncated in [false, true]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final direct = HttpClient();
        var finished = false;
        var firstWasBeforeFinished = false;
        final firstText = Completer<void>();
        final partials = <String>[];
        final received = server.first.then((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['stream'], isTrue);
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.bufferOutput = false;
          final frame = utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': 'Sesión 💪'},
                },
              ],
            })}\r\n\r\n',
          );
          for (final byte in frame) {
            request.response.add([byte]);
          }
          await request.response.flush();
          await firstText.future.timeout(const Duration(seconds: 3));
          if (!truncated) {
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': ' lista'},
                    'finish_reason': 'stop',
                  },
                ],
              })}\n\ndata: [DONE]\n\n',
            );
          }
          finished = true;
          await request.response.close();
        });
        try {
          final call = HttpOverrides.runZoned(
            () => AiClient().reply(
              config(AiProtocol.chatCompletions),
              const [AiMessage('user', 'Prepara')],
              system: 's',
              sessionId: 'stream-regression',
              onText: (text) {
                if (partials.isEmpty) {
                  firstWasBeforeFinished = !finished;
                  firstText.complete();
                }
                partials.add(text);
              },
            ),
            createHttpClient:
                (_) => _LoopbackHttpClient(
                  direct,
                  Uri.parse('http://127.0.0.1:${server.port}/chat/completions'),
                ),
          );
          if (truncated) {
            await expectLater(call, throwsA(isA<ValidationException>()));
          } else {
            expect(await call, 'Sesión 💪 lista');
          }
          expect(partials.first, 'Sesión 💪');
          expect(firstWasBeforeFinished, isTrue);
          await received;
        } finally {
          direct.close(force: true);
          await server.close(force: true);
        }
      }
    },
  );
  test(
    'GLM-5.3 image is rejected before transport; Flash is not confused with it',
    () async {
      var sent = false;
      final client = AiClient(
        transport: (_, __, ___) async {
          sent = true;
          return {
            'choices': [
              {
                'message': {'content': 'Foto recibida'},
              },
            ],
          };
        },
      );
      final photo = AiAttachment(
        name: 'photo.png',
        mime: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      AiConfig model(String id) => AiConfig(
        service: AiService.opencodeGo,
        baseUrl: AiService.opencodeGo.baseUrl,
        model: id,
        protocol: AiProtocol.chatCompletions,
        apiKey: 'test-key',
      );
      await expectLater(
        client.reply(
          model('opencode-go/glm-5.3'),
          [AiMessage('user', 'Mira', attachment: photo)],
          system: 's',
          sessionId: 's',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains('solo texto'),
          ),
        ),
      );
      expect(sent, false);
      expect(
        await client.reply(
          model('glm-5.3-flash'),
          [AiMessage('user', 'Mira', attachment: photo)],
          system: 's',
          sessionId: 's',
        ),
        'Foto recibida',
      );
      expect(sent, true);
    },
  );
  test(
    'HTTP preserves emoji and accented history on subsequent turns',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final direct = HttpClient();
      final received = server.first.then((request) async {
        expect(request.headers.contentType?.charset, 'utf-8');
        final payload =
            jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(payload['messages'][1]['content'], 'Hola');
        expect(
          payload['messages'][2]['content'],
          '¡Hola! 👋 Sesión de entrenamiento',
        );
        expect(payload['messages'][3]['content'], '¿En qué vamos? 🏋️');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Tu sesión está activa 💪'},
              },
            ],
          }),
        );
        await request.response.close();
      });
      try {
        final answer = await HttpOverrides.runZoned(
          () => AiClient().reply(
            config(AiProtocol.chatCompletions),
            const [
              AiMessage('user', 'Hola'),
              AiMessage('assistant', '¡Hola! 👋 Sesión de entrenamiento'),
              AiMessage('user', '¿En qué vamos? 🏋️'),
            ],
            system: 'Habla en español.',
            sessionId: 'utf8-regression',
          ),
          createHttpClient:
              (_) => _LoopbackHttpClient(
                direct,
                Uri.parse('http://127.0.0.1:${server.port}/chat/completions'),
              ),
        );
        expect(answer, 'Tu sesión está activa 💪');
        await received;
      } finally {
        direct.close(force: true);
        await server.close(force: true);
      }
    },
  );
  test(
    'images use each provider format and are not serialized into transcript',
    () async {
      final media = AiAttachment(
        name: 'photo.png',
        mime: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      for (final protocol in AiProtocol.values) {
        final message = AiMessage(
          'user',
          '¿Qué máquina es?',
          attachment: media,
        );
        final encoded = message.forApi(protocol);
        final content = encoded['content'] as List;
        expect(content.length, 2);
        final image = content.last as Map;
        switch (protocol) {
          case AiProtocol.chatCompletions:
            expect(image['image_url']['url'], 'data:image/png;base64,AQID');
          case AiProtocol.responses:
            expect(image['image_url'], 'data:image/png;base64,AQID');
          case AiProtocol.anthropic:
            expect(image['source']['data'], 'AQID');
          case AiProtocol.gemini:
            expect(image['inlineData']['data'], 'AQID');
        }
        expect(message.toJson().toString(), isNot(contains('AQID')));
      }
    },
  );
  test(
    'audio is sent to Gemini and blocked before transport for other formats',
    () async {
      final media = AiAttachment(
        name: 'voice.mp3',
        mime: 'audio/mpeg',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      var sent = false;
      final client = AiClient(
        transport: (_, __, body) async {
          sent = true;
          expect(
            (body['contents'] as List)
                .last['parts'][1]['inlineData']['mimeType'],
            'audio/mpeg',
          );
          return {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Audio entendido'},
                  ],
                },
              },
            ],
          };
        },
      );
      for (final protocol in [
        AiProtocol.chatCompletions,
        AiProtocol.responses,
        AiProtocol.anthropic,
      ]) {
        await expectLater(
          client.reply(
            config(protocol),
            [AiMessage('user', 'Audio', attachment: media)],
            system: 'system',
            sessionId: 's',
          ),
          throwsA(isA<ValidationException>()),
        );
        expect(sent, false);
      }
      expect(
        await client.reply(
          config(AiProtocol.gemini, service: AiService.gemini),
          [AiMessage('user', 'Audio', attachment: media)],
          system: 'system',
          sessionId: 's',
        ),
        'Audio entendido',
      );
    },
  );
  test('OpenCode CLI model identifiers are normalized for the API', () {
    const go = AiConfig(
      service: AiService.opencodeGo,
      baseUrl: 'https://opencode.ai/zen/go/v1',
      model: 'opencode-go/glm-5.2',
      protocol: AiProtocol.chatCompletions,
      apiKey: 'test-key',
    );
    expect(go.modelId, 'glm-5.2');
    go.validate();
  });
  const messages = [AiMessage('user', '¿Qué ejercicio hice?')];
  test(
    'Go uses its endpoint, truthful user agent and stable conversation session',
    () async {
      final sessions = <String>[];
      final client = AiClient(
        transport: (uri, headers, body) async {
          expect(
            uri.toString(),
            'https://opencode.ai/zen/go/v1/chat/completions',
          );
          expect(headers['User-Agent'], 'GymIA/0.3.14');
          expect(headers['Authorization'], 'Bearer test-secret');
          sessions.add(headers['x-opencode-session']!);
          expect(body['messages'], [
            {'role': 'system', 'content': 'system'},
            messages.single.toJson(),
          ]);
          return {
            'choices': [
              {
                'message': {'content': 'Hola'},
              },
            ],
          };
        },
      );
      for (var i = 0; i < 2; i++) {
        expect(
          await client.reply(
            config(AiProtocol.chatCompletions),
            messages,
            system: 'system',
            sessionId: 'conversation-1',
          ),
          'Hola',
        );
      }
      expect(sessions, ['conversation-1', 'conversation-1']);
    },
  );
  test(
    'Responses extracts message text and ignores reasoning blocks',
    () async {
      final client = AiClient(
        transport: (uri, headers, body) async {
          expect(uri.path, '/v1/responses');
          expect(headers.containsKey('x-opencode-session'), isFalse);
          expect(body['store'], false);
          expect(body['instructions'], 'system');
          return {
            'status': 'completed',
            'output': [
              {'type': 'reasoning', 'summary': []},
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
          config(AiProtocol.responses, service: AiService.openai),
          messages,
          system: 'system',
          sessionId: 's',
        ),
        'Respuesta',
      );
    },
  );
  test('Anthropic sends correct headers and system separately', () async {
    final client = AiClient(
      transport: (uri, headers, body) async {
        expect(uri.path, '/v1/messages');
        expect(headers['x-api-key'], 'test-secret');
        expect(headers.containsKey('Authorization'), isFalse);
        expect(headers['anthropic-version'], '2023-06-01');
        expect(body['system'], 'system');
        return {
          'content': [
            {'type': 'thinking', 'thinking': 'private'},
            {'type': 'text', 'text': 'Respuesta'},
          ],
        };
      },
    );
    expect(
      await client.reply(
        config(AiProtocol.anthropic, service: AiService.anthropic),
        messages,
        system: 'system',
        sessionId: 's',
      ),
      'Respuesta',
    );
  });
  test('Gemini uses model path and excludes thought text', () async {
    final client = AiClient(
      transport: (uri, headers, body) async {
        expect(uri.path, '/v1beta/models/test-model:generateContent');
        expect(uri.query, '');
        expect(headers['x-goog-api-key'], 'test-secret');
        expect((body['contents'] as List).last['role'], 'user');
        return {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'private', 'thought': true},
                  {'text': 'Respuesta'},
                ],
              },
            },
          ],
        };
      },
    );
    expect(
      await client.reply(
        config(AiProtocol.gemini, service: AiService.gemini),
        messages,
        system: 'system',
        sessionId: 's',
      ),
      'Respuesta',
    );
  });
  test('invalid endpoint never sends credentials', () async {
    var sent = false;
    final client = AiClient(
      transport: (_, __, ___) async {
        sent = true;
        return {};
      },
    );
    for (final base in [
      'http://example.com/v1',
      'https://example.com/v1?key=secret',
      'https://u:p@example.com/v1',
    ]) {
      await expectLater(
        client.reply(
          config(AiProtocol.chatCompletions, base: base),
          messages,
          system: 'system',
          sessionId: 's',
        ),
        throwsA(isA<ValidationException>()),
      );
    }
    expect(sent, isFalse);
  });
  test(
    'invalid provider response becomes useful error without exposing response',
    () async {
      final client = AiClient(
        transport: (_, __, ___) async => {'error': 'test-secret'},
      );
      await expectLater(
        client.reply(
          config(AiProtocol.responses),
          messages,
          system: 'system',
          sessionId: 's',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            isNot(contains('test-secret')),
          ),
        ),
      );
    },
  );
  test('partial Responses output is not presented as complete', () async {
    final client = AiClient(
      transport: (_, __, ___) async => {'status': 'incomplete', 'output': []},
    );
    await expectLater(
      client.reply(
        config(AiProtocol.responses),
        messages,
        system: 'system',
        sessionId: 's',
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
