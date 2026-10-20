import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.gymia.app/rest-notifications');
  testWidgets('immediate notification test works without an activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Sin actividad'))),
    );
    await tester.runAsync(() async {
      final status = await channel.invokeMapMethod<String, dynamic>('status');
      expect(status?['granted'], isTrue);
      expect(
        await channel.invokeMethod<bool>('enable', {'enabled': true}),
        isTrue,
      );
      expect(await channel.invokeMethod<bool>('test'), isTrue);
    });
  });
  testWidgets(
    'native Android rest alarm survives sending the activity to background',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Prueba de avisos · no es un entrenamiento real'),
            ),
          ),
        ),
      );
      // The emulator grant is made externally after the test APK is installed.
      await tester.runAsync(() async {
        final limit = DateTime.now().add(const Duration(seconds: 60));
        while (true) {
          final status = await channel.invokeMapMethod<String, dynamic>(
            'status',
          );
          if (status?['granted'] == true && status?['exact'] == true) break;
          if (DateTime.now().isAfter(limit)) {
            throw StateError(
              'Grant POST_NOTIFICATIONS and exact alarms to the test package before this smoke test.',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(
          await channel.invokeMethod<bool>('enable', {'enabled': true}),
          isTrue,
        );
        final end =
            DateTime.now()
                .add(const Duration(seconds: 8))
                .millisecondsSinceEpoch;
        await channel.invokeMethod<void>('schedule', {
          'id': 'native-smoke',
          'end': end,
          'name': 'Prueba de interfaz',
        });
        // Allows adb to send Home and inspect the delivered native notification.
        await Future<void>.delayed(const Duration(seconds: 25));
        final result = await channel.invokeMapMethod<String, dynamic>('status');
        expect(result?['lastDeliveredId'], 'native-smoke');
        expect(result?['lastDeliveredEnd'], end);
      });
    },
  );
}
