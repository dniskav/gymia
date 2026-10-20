import 'package:flutter/material.dart';
import '../data/welcome_settings_store.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.settings});

  final WelcomeSettings? settings;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final WelcomeSettings settings =
      widget.settings ?? WelcomeSettings.instance;
  final PageController pages = PageController();
  int index = 0;
  late bool doNotShowAgain = !settings.autoShow;
  bool saving = false;

  static const slides = <({IconData icon, String title, String body})>[
    (
      icon: Icons.auto_awesome_outlined,
      title: 'Bienvenido',
      body:
          'Conversa con tu asistente de IA para preparar una actividad, resolver dudas y revisar tu progreso. Tú decides cuándo empezar.',
    ),
    (
      icon: Icons.chat_bubble_outline,
      title: 'Habla o escribe',
      body:
          'El chat admite texto, dictado y adjuntos. Para usar la IA, conecta un proveedor desde el menú. Si se corta la conexión, tus registros locales siguen disponibles.',
    ),
    (
      icon: Icons.play_circle_outline,
      title: 'Controla tu actividad',
      body:
          'Elige o crea una actividad. Prepararla no inicia el reloj: pulsa Iniciar cuando estés listo y Parar al terminar cada tramo.',
    ),
    (
      icon: Icons.save_outlined,
      title: 'Conserva tus datos',
      body:
          'Tus registros se guardan en el móvil. Puedes conectar Google Sheets cuando quieras y revisar el estado de cada envío.',
    ),
    (
      icon: Icons.tune_outlined,
      title: 'A tu manera',
      body:
          'Elige tema claro u oscuro y consulta tus chats archivados. Esta guía siempre estará disponible en Ayuda.',
    ),
  ];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await settings.select(!doNotShowAgain, completed: true);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      final leave = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('No se pudo guardar la elección'),
              content: const Text(
                'Puedes volver a intentarlo o continuar. Si continúas, la bienvenida podría aparecer al abrir la app de nuevo.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Reintentar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continuar sin guardar'),
                ),
              ],
            ),
      );
      if (leave == true && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bienvenida')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Paso ${index + 1} de ${slides.length}',
                key: const Key('welcome-progress'),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              key: const Key('welcome-pages'),
              controller: pages,
              itemCount: slides.length,
              onPageChanged: (next) => setState(() => index = next),
              itemBuilder: (context, i) {
                final slide = slides[i];
                return SingleChildScrollView(
                  key: ValueKey('welcome-slide-$i'),
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      if (i == 0)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/branding/trackia-logo.png',
                            key: const Key('welcome-trackia-logo'),
                            width: 190,
                            height: 190,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        Icon(
                          slide.icon,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      const SizedBox(height: 24),
                      Text(
                        slide.title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        slide.body,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (i) {
                final active = i == index;
                return Semantics(
                  label: 'Página ${i + 1} de ${slides.length}',
                  selected: active,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedContainer(
                      key: Key('welcome-dot-$i'),
                      duration: const Duration(milliseconds: 180),
                      width: active ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            active
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(
            height: 148,
            child: SingleChildScrollView(
              child: CheckboxListTile(
                key: const Key('welcome-never-again'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: const Text('No volver a mostrar'),
                subtitle: const Text(
                  'Si la dejas sin marcar, verás esta guía al abrir la app. Puedes cambiarlo en Ayuda.',
                ),
                value: doNotShowAgain,
                onChanged:
                    saving
                        ? null
                        : (value) =>
                            setState(() => doNotShowAgain = value ?? false),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: [
                TextButton(
                  key: const Key('welcome-skip'),
                  onPressed: saving ? null : finish,
                  child: const Text('Omitir'),
                ),
                if (index > 0)
                  TextButton(
                    key: const Key('welcome-back'),
                    onPressed:
                        saving
                            ? null
                            : () => pages.previousPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            ),
                    child: const Text('Anterior'),
                  ),
                FilledButton(
                  key: const Key('welcome-next'),
                  onPressed:
                      saving
                          ? null
                          : index == slides.length - 1
                          ? finish
                          : () => pages.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          ),
                  child: Text(
                    index == slides.length - 1 ? 'Empezar' : 'Siguiente',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class WelcomeHelpScreen extends StatelessWidget {
  const WelcomeHelpScreen({super.key, this.settings});
  final WelcomeSettings? settings;

  @override
  Widget build(BuildContext context) {
    final preference = settings ?? WelcomeSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y bienvenida')),
      body: ListenableBuilder(
        listenable: preference,
        builder:
            (context, _) => ListView(
              children: [
                SwitchListTile(
                  key: const Key('welcome-auto-show'),
                  title: const Text('Mostrar bienvenida al abrir'),
                  subtitle: const Text(
                    'Tu elección se guarda en este dispositivo.',
                  ),
                  value: preference.autoShow,
                  onChanged:
                      preference.busy
                          ? null
                          : (value) async {
                            try {
                              await preference.select(value);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No se pudo guardar la preferencia.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                ),
                ListTile(
                  leading: const Icon(Icons.slideshow_outlined),
                  title: const Text('Ver bienvenida'),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WelcomeScreen(settings: preference),
                        ),
                      ),
                ),
              ],
            ),
      ),
    );
  }
}
