import 'package:flutter/material.dart';
import 'data/sqlite_workout_repository.dart';
import 'application/workout_controller.dart';
import 'ui/app.dart';
import 'ui/theme.dart' show gymLightTheme;
import 'data/profile_store.dart';
import 'data/theme_settings.dart';
import 'data/welcome_settings_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.databaseDirectory});
  final String? databaseDirectory;
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  final profiles = ProfileStore.instance;
  final controllers = <String, WorkoutController>{};
  @override
  void initState() {
    super.initState();
    profiles.addListener(profileChanged);
  }

  void profileChanged() {
    if (mounted) {
      setState(() {
        future = _open(loadRegistry: false);
      });
    }
  }

  late Future<WorkoutController> future = _open();
  Future<WorkoutController> _open({bool loadRegistry = true}) async {
    if (loadRegistry) {
      try {
        await ThemeSettings.instance.load();
      } catch (_) {
        /* Keep dark if settings are unavailable. */
      }
      try {
        await WelcomeSettings.instance.load();
      } catch (_) {
        /* A missing preference means the welcome remains available. */
      }
      await profiles.load();
    }
    final id = profiles.activeId;
    if (controllers.containsKey(id)) return controllers[id]!;
    final path =
        id == 'local' && widget.databaseDirectory == null
            ? null
            : p.join(
              widget.databaseDirectory ?? await getDatabasesPath(),
              id == 'local' ? 'gymia.sqlite' : 'gymia-$id.sqlite',
            );
    final repository = await SqliteWorkoutRepository.open(path: path);
    final controller = WorkoutController(repository, profileId: id);
    await controller.refresh();
    if (!controller.loaded) {
      controller.dispose();
      await repository.close();
      throw StateError('No se pudo abrir el perfil.');
    }
    controllers[id] = controller;
    return controller;
  }

  @override
  void dispose() {
    profiles.removeListener(profileChanged);
    for (final controller in controllers.values) {
      controller.dispose();
      // Repositories remain open until process exit so captured writes from
      // disposed screens can finish in their original profile.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkoutController>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        return GymApp(
          key: ValueKey(snapshot.data!.profileId),
          controller: snapshot.data!,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: gymLightTheme,
        darkTheme: gymTheme,
        themeMode: ThemeSettings.instance.mode,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child:
                  snapshot.hasError
                      ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storage_rounded, size: 40),
                          const SizedBox(height: 16),
                          const Text(
                            'No se pudo abrir tu bitácora. Tus datos no se han borrado.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed:
                                () => setState(() {
                                  future = _open();
                                }),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      )
                      : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}
