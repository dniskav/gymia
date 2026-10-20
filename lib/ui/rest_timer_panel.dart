import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/workout_controller.dart';
import '../domain/rest_timer.dart';
import '../domain/routine.dart';
import '../domain/workout.dart';
import 'theme.dart';

class RestTimerPanel extends StatefulWidget {
  const RestTimerPanel({
    super.key,
    required this.controller,
    required this.workout,
  });
  final WorkoutController controller;
  final Workout workout;
  @override
  State<RestTimerPanel> createState() => _RestTimerPanelState();
}

class _RestTimerPanelState extends State<RestTimerPanel>
    with WidgetsBindingObserver {
  late final Timer ticker;
  bool wasRunning = false;
  bool foreground = true;
  WorkoutController get c => widget.controller;
  RestTimerState get state =>
      c.restTimer?.workoutId == widget.workout.id
          ? c.restTimer!
          : RestTimerState(
            workoutId: widget.workout.id,
            durationSeconds:
                widget.workout.exercises.firstOrNull?.restSeconds ?? 90,
            remainingMs:
                (widget.workout.exercises.firstOrNull?.restSeconds ?? 90) *
                1000,
          );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    wasRunning = state.runningAt(DateTime.now());
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState status) {
    foreground = status == AppLifecycleState.resumed;
    if (foreground) tick();
  }

  void tick() {
    if (!mounted || !foreground) return;
    final running = state.runningAt(DateTime.now());
    if (wasRunning && !running && state.remainingAt(DateTime.now()) == 0) {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.mediumImpact());
    }
    if (wasRunning || running) setState(() {});
    wasRunning = running;
  }

  @override
  void dispose() {
    ticker.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> configure() async {
    final seconds = await showDialog<int>(
      context: context,
      builder: (_) => RestDurationDialog(seconds: state.durationSeconds),
    );
    if (seconds != null) {
      await c.run(() => c.repository.resetRest(widget.workout.id, seconds));
    }
  }

  @override
  Widget build(BuildContext context) {
    final timer = state;
    final now = DateTime.now();
    final running = timer.runningAt(now);
    final remaining = timer.remainingAt(now);
    final paused =
        timer.endsAt == null &&
        remaining > 0 &&
        remaining < timer.durationSeconds * 1000;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: lime, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Descanso terminado'
                      : paused
                      ? 'Descanso pausado'
                      : 'Descanso',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Semantics(
                liveRegion: remaining == 0,
                label: remaining == 0 ? 'Descanso terminado' : null,
                child: Text(
                  timer.displayAt(now),
                  key: const Key('rest-clock'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: lime,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed:
                    c.busy
                        ? null
                        : () => c.run(
                          () =>
                              running
                                  ? c.repository.pauseRest(widget.workout.id)
                                  : paused
                                  ? c.repository.resumeRest(widget.workout.id)
                                  : c.repository.startRest(
                                    widget.workout.id,
                                    timer.durationSeconds,
                                  ),
                        ),
                icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 20),
                label: Text(
                  running
                      ? 'Pausar'
                      : paused
                      ? 'Continuar'
                      : 'Iniciar descanso',
                ),
              ),
              IconButton(
                tooltip: 'Reiniciar descanso',
                onPressed:
                    c.busy
                        ? null
                        : () => c.run(
                          () => c.repository.startRest(
                            widget.workout.id,
                            timer.durationSeconds,
                          ),
                        ),
                icon: const Icon(Icons.replay, size: 20),
              ),
              TextButton(
                onPressed: c.busy ? null : configure,
                child: Text('${timer.durationSeconds}s · Ajustar'),
              ),
            ],
          ),
          const Text(
            'Aviso con esta pantalla abierta; el tiempo sigue al salir.',
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class RestDurationDialog extends StatefulWidget {
  const RestDurationDialog({super.key, required this.seconds});
  final int seconds;
  @override
  State<RestDurationDialog> createState() => _RestDurationDialogState();
}

class _RestDurationDialogState extends State<RestDurationDialog> {
  late final input = TextEditingController(text: '${widget.seconds}');
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tiempo de descanso'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('timer-duration'),
              controller: input,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Segundos',
                errorMaxLines: 2,
              ),
              validator: (v) {
                try {
                  parseRestSeconds(v ?? '');
                  return null;
                } on ValidationException catch (e) {
                  return e.message;
                }
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Entre 5 y 1800 segundos. Al aplicar, el contador queda listo para empezar.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, parseRestSeconds(input.text));
          }
        },
        child: const Text('Aplicar'),
      ),
    ],
  );
}
