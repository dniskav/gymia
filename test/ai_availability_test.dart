import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gymia/application/ai_availability.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/data/ai_model_catalog.dart';
import 'package:gymia/data/ai_settings_store.dart';
import 'package:gymia/domain/ai_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  const config = AiConfig(
    service: AiService.custom,
    protocol: AiProtocol.chatCompletions,
    baseUrl: 'https://example.test/v1',
    model: 'model',
    apiKey: 'fake-key',
  );
  const store = AiSettingsStore();

  test(
    'missing key and saved but unverified model never call inference automatically',
    () async {
      var calls = 0;
      final status = AiAvailability(
        client: AiClient(
          transport: (_, __, ___) async {
            calls++;
            return {
              'choices': [
                {
                  'message': {'content': 'OK'},
                },
              ],
            };
          },
        ),
      );
      addTearDown(status.dispose);
      await status.check();
      expect(status.status, AiAvailabilityStatus.unconfigured);
      await store.save(config);
      await status.check();
      expect(status.status, AiAvailabilityStatus.unverified);
      expect(calls, 0);
      await status.check(verify: true);
      expect(status.ready, isTrue);
      expect(calls, 1);
      expect(await store.isVerified(config), isTrue);
      await store.delete();
      await status.check();
      expect(status.ready, isFalse);
    },
  );

  test(
    'catalog reconnects verified model; offline and removed model disable it without paid polling',
    () async {
      await store.save(config);
      await store.markVerified(config);
      var offline = false, present = true, inference = 0;
      final status = AiAvailability(
        catalog: AiModelCatalog(
          transport: (_, __) async {
            if (offline) throw StateError('offline');
            return {
              'data': [
                {'id': present ? 'model' : 'another'},
              ],
            };
          },
        ),
        client: AiClient(
          transport: (_, __, ___) async {
            inference++;
            return {};
          },
        ),
      );
      addTearDown(status.dispose);
      await status.check();
      expect(status.ready, isTrue);
      offline = true;
      await status.check();
      expect(status.ready, isFalse);
      offline = false;
      present = false;
      await status.check();
      expect(status.status, AiAvailabilityStatus.unverified);
      present = true;
      await status.check();
      expect(status.ready, isTrue);
      expect(inference, 0);
    },
  );

  test(
    'late verification cannot enable a configuration that was deleted',
    () async {
      await store.save(config);
      final reply = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final status = AiAvailability(
        client: AiClient(
          transport: (_, __, ___) {
            started.complete();
            return reply.future;
          },
        ),
      );
      addTearDown(status.dispose);
      final checking = status.check(verify: true);
      await started.future;
      await store.delete();
      reply.complete({
        'choices': [
          {
            'message': {'content': 'OK'},
          },
        ],
      });
      await checking;
      expect(status.status, AiAvailabilityStatus.unconfigured);
    },
  );
}
