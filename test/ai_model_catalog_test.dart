import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/workout.dart';
import 'package:gymia/ui/ai_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  AiConfig config(
    AiService service, {
    String model = '',
    String? base,
    AiProtocol? protocol,
  }) => AiConfig(
    service: service,
    baseUrl: base ?? service.baseUrl,
    model: model,
    protocol: protocol ?? service.defaultProtocol,
    apiKey: 'catalog-secret',
  );

  test(
    'catalog uses selected provider URL, live IDs, auth headers and no chat request',
    () async {
      for (final service in [
        AiService.opencodeGo,
        AiService.opencodeZen,
        AiService.openai,
        AiService.openrouter,
        AiService.deepseek,
        AiService.minimax,
        AiService.kimi,
        AiService.custom,
      ]) {
        final selected = config(
          service,
          base:
              service == AiService.custom
                  ? 'https://example.test/proxy/v1/'
                  : null,
        );
        final client = AiModelCatalog(
          transport: (uri, headers) async {
            expect(
              uri.toString(),
              '${selected.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/models',
            );
            expect(uri.hasQuery, isFalse);
            expect(headers['Authorization'], 'Bearer catalog-secret');
            return {
              'data': [
                {'id': 'future-model-428'},
                {'id': 'future-model-429'},
                {'id': 'future-model-428'},
              ],
            };
          },
        );
        expect((await client.list(selected)).map((m) => m.id), [
          'future-model-428',
          'future-model-429',
        ]);
      }
    },
  );

  test(
    'native catalogs paginate and Gemini keeps generation models only',
    () async {
      var pages = 0;
      final gemini = AiModelCatalog(
        transport: (uri, headers) async {
          expect(headers['x-goog-api-key'], 'catalog-secret');
          expect(headers.containsKey('Authorization'), isFalse);
          pages++;
          if (pages == 1) {
            return {
              'models': [
                {
                  'name': 'models/embedding-new',
                  'supportedGenerationMethods': ['embedContent'],
                },
                {
                  'name': 'models/generation-new',
                  'displayName': 'Nuevo modelo',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
              'nextPageToken': 'page-two',
            };
          }
          expect(uri.queryParameters['pageToken'], 'page-two');
          return {
            'models': [
              {
                'name': 'models/another-new',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          };
        },
      );
      expect((await gemini.list(config(AiService.gemini))).map((m) => m.id), [
        'generation-new',
        'another-new',
      ]);
      pages = 0;
      final claude = AiModelCatalog(
        transport: (uri, headers) async {
          expect(headers['x-api-key'], 'catalog-secret');
          expect(headers['anthropic-version'], '2023-06-01');
          pages++;
          if (pages == 1) {
            return {
              'data': [
                {'id': 'new-claude'},
              ],
              'has_more': true,
              'last_id': 'new-claude',
            };
          }
          expect(uri.queryParameters['after_id'], 'new-claude');
          return {
            'data': [
              {'id': 'another-claude'},
            ],
            'has_more': false,
          };
        },
      );
      expect(
        (await claude.list(config(AiService.anthropic))).map((m) => m.id),
        ['new-claude', 'another-claude'],
      );
    },
  );

  test(
    'uses capability metadata, rejects bad URLs before sending credentials and handles unsupported catalogs',
    () async {
      var calls = 0;
      final catalog = AiModelCatalog(
        transport: (_, __) async {
          calls++;
          return {
            'data': [
              {
                'id': 'new-image-only',
                'architecture': {
                  'output_modalities': ['image'],
                },
              },
              {
                'id': 'new-chat',
                'architecture': {
                  'input_modalities': ['text', 'image'],
                  'output_modalities': ['text'],
                },
              },
            ],
          };
        },
      );
      await expectLater(
        catalog.list(
          config(AiService.custom, base: 'https://example.test/v1?api_key=bad'),
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(calls, 0);
      final result = await catalog.list(config(AiService.openrouter));
      expect(result.single.id, 'new-chat');
      expect(result.single.acceptsImages, isTrue);
      await expectLater(
        AiModelCatalog(
          transport: (_, __) async => {'unknown': []},
        ).list(config(AiService.deepseek)),
        throwsA(isA<ValidationException>()),
      );
    },
  );

  testWidgets(
    'API key loads live models, selects a catalog default and saves selected model',
    (tester) async {
      var calls = 0;
      final catalog = AiModelCatalog(
        transport: (_, __) async {
          calls++;
          return {
            'data': [
              {'id': 'runtime-v42'},
              {'id': 'runtime-v43'},
            ],
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: AiSettingsScreen(catalog: catalog)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ai-api-key')), 'new-secret');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'runtime-v42',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('runtime-v43').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guardar proveedor'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Guardar proveedor'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar proveedor'));
      await tester.pumpAndSettle();
      expect((await const AiSettingsStore().load())!.model, 'runtime-v43');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved model absent from fresh catalog is preserved, not silently replaced',
    (tester) async {
      await const AiSettingsStore().save(
        config(AiService.deepseek, model: 'previous-model'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiSettingsScreen(
            catalog: AiModelCatalog(
              transport:
                  (_, __) async => {
                    'data': [
                      {'id': 'newer-model'},
                    ],
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Modelo actual: previous-model'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
      expect((await const AiSettingsStore().load())!.model, 'previous-model');
    },
  );

  testWidgets('late result from previous key cannot replace the new catalog', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final catalog = AiModelCatalog(
      transport:
          (_, headers) =>
              headers['Authorization'] == 'Bearer first-key'
                  ? first.future
                  : second.future,
    );
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsScreen(catalog: catalog)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-api-key')), 'first-key');
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('ai-api-key')), 'second-key');
    await tester.pump(const Duration(seconds: 1));
    first.complete({
      'data': [
        {'id': 'stale-model'},
      ],
    });
    await tester.pump();
    second.complete({
      'data': [
        {'id': 'current-model'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('current-model'), findsOneWidget);
    expect(find.text('stale-model'), findsNothing);
  });
}
