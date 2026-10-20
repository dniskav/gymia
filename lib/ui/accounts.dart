import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/profile_store.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool busy = false;
  String? error;
  final profiles = ProfileStore.instance;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = switch (e) {
                PlatformException p =>
                  p.message ?? 'No se pudo conectar con Google.',
                FormatException f => f.message,
                _ => 'No se pudo cambiar de cuenta. Tus datos se conservan.',
              },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cuenta y datos')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          profiles.active?.email ?? 'Perfil local',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'Cada cuenta tiene su conversación, configuración de IA, hoja y entrenamientos en este móvil. El histórico anterior permanece en el perfil local. Conectar no copia ni sube esos datos.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : () => run(() => profiles.connect()),
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Conectar otra cuenta de Google'),
        ),
        for (final profile in profiles.profiles)
          ListTile(
            title: Text(profile.email),
            subtitle: Text(
              profile.id == profiles.activeId
                  ? 'Perfil activo'
                  : 'Volver a este perfil con Google',
            ),
            trailing:
                profile.id == profiles.activeId
                    ? const Icon(Icons.check)
                    : null,
            enabled: !busy && profile.id != profiles.activeId,
            onTap:
                () => run(
                  () => profiles.connect(expectedSubject: profile.subject),
                ),
          ),
        if (profiles.activeId != 'local') ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : () => run(profiles.useLocal),
            child: const Text('Desconectar y volver al perfil local'),
          ),
          const Text(
            'Desconectar conserva los datos de cada perfil en este móvil. No borra archivos de Google ni revoca el acceso desde tu cuenta de Google.',
          ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
