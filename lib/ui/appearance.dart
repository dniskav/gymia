import 'package:flutter/material.dart';
import '../data/theme_settings.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, this.settings});
  final ThemeSettings? settings;
  @override
  Widget build(BuildContext context) {
    final preference = settings ?? ThemeSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Apariencia')),
      body: ListenableBuilder(
        listenable: preference,
        builder:
            (context, _) => ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Elige cómo quieres ver TrackIA. La elección se guarda en este móvil.',
                  ),
                ),
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    key: ValueKey('theme-${mode.name}'),
                    title: Text(switch (mode) {
                      ThemeMode.system => 'Automático',
                      ThemeMode.light => 'Claro',
                      ThemeMode.dark => 'Oscuro',
                    }),
                    subtitle:
                        mode == ThemeMode.system
                            ? const Text('Usar el tema del dispositivo')
                            : null,
                    value: mode,
                    groupValue: preference.mode,
                    onChanged:
                        preference.busy
                            ? null
                            : (value) async {
                              if (value == null) return;
                              try {
                                await preference.select(value);
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No se pudo guardar el tema. Vuelve a intentarlo.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                  ),
              ],
            ),
      ),
    );
  }
}
