import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/ui/app.dart';

void main() {
  testWidgets('series dialog validates before returning a record', (
    tester,
  ) async {
    SetInput? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: gymTheme,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<SetInput>(
                      context: context,
                      builder: (_) => const SetDialog(),
                    );
                  },
                  child: const Text('Abrir'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weight-input')), '-3');
    await tester.enterText(find.byKey(const Key('reps-input')), '0');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('Introduce entre'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('weight-input')), '20,5');
    await tester.enterText(find.byKey(const Key('reps-input')), '12');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result?.weight, '20,5');
    expect(result?.reps, '12');
    expect(tester.takeException(), isNull);
  });
}
