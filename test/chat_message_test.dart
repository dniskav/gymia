import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/ui/chat_message.dart';
import 'package:gymia/ui/theme.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

void main() {
  testWidgets('assistant tables wrap on phone and actions stay out of chat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              ChatMessageBody(
                assistant: true,
                text:
                    '**Chest Press**\n\n'
                    '| Serie | Peso | Repeticiones |\n'
                    '| --- | --- | --- |\n'
                    '| Primera serie | 60 kg | 13 al fallo |\n\n'
                    '```gymia-activity\n{"name":"Chest Press"}\n```',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chest Press'), findsOneWidget);
    expect(find.text('**Chest Press**'), findsNothing);
    expect(find.byType(Table), findsOneWidget);
    expect(find.textContaining('gymia-activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model image markup does not read files or download images', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageBody(
            assistant: true,
            text:
                '![Ejercicio](https://example.test/photo.png)\n\n'
                '![Privado](/data/user/0/com.gymia.app/private.png)',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ejercicio'), findsOneWidget);
    expect(find.text('Privado'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unfinished streamed action is hidden until completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatMessageBody(
            assistant: true,
            text: 'Preparando ejercicio.\n```gymia-activity\n{"name":"Chest',
          ),
        ),
      ),
    );
    expect(find.text('Preparando ejercicio.'), findsOneWidget);
    expect(find.textContaining('gymia-activity'), findsNothing);
    expect(find.textContaining('Chest'), findsNothing);
  });
  for (final theme in [gymTheme, gymLightTheme]) {
    testWidgets(
      'quotes and code have readable ${theme.brightness.name}-theme contrast on a phone',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: ChatMessageBody(
                  assistant: true,
                  text:
                      '> Solicitud: sincronización automática a Google Sheets\n>\n> 1. Guardar permiso una vez.\n> 2. Enviar al finalizar.\n\n```text\n60 kg × 10 repeticiones\n```',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final style =
            tester.widget<MarkdownBody>(find.byType(MarkdownBody)).styleSheet!;
        double ratio(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
        }

        final background = (style.blockquoteDecoration as BoxDecoration).color!;
        expect(
          ratio(style.blockquote!.color!, background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          ratio(
            style.code!.color!,
            (style.codeblockDecoration as BoxDecoration).color!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), null);
      },
    );
  }
}
