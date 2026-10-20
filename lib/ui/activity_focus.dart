import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../application/workout_controller.dart';
import '../domain/activity.dart';
import '../domain/workout.dart';
import 'session_control.dart';

class ActivityFocusControls extends StatefulWidget {
  const ActivityFocusControls({
    super.key,
    required this.controller,
    required this.flushInput,
    this.compact = false,
    this.aiReady = true,
    this.hideStart = false,
  });
  final WorkoutController controller;
  final Future<void> Function() flushInput;
  final bool compact;
  final bool aiReady;
  final bool hideStart;
  @override
  State<ActivityFocusControls> createState() => _ActivityFocusControlsState();
}

class _ActivityFocusControlsState extends State<ActivityFocusControls>
    with WidgetsBindingObserver {
  WorkoutController get c => widget.controller;
  late final Timer ticker;
  bool acting = false, foreground = true;
  FocusActivity? get resting {
    final focus = c.focus;
    if (focus?.running != null) return null;
    if (focus?.restEndsAt != null) return focus;
    return c.activities
        .where((a) => a.restEndsAt?.isAfter(c.now()) ?? false)
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !foreground) return;
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      foreground = state == AppLifecycleState.resumed;
  @override
  void dispose() {
    ticker.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> act() async {
    final a = c.focus;
    if (a == null || acting || c.busy) return;
    if (a.running == null && (!widget.aiReady || widget.hideStart)) return;
    setState(() => acting = true);
    try {
      if (a.running != null) {
        await c.run(() => c.activityRepository!.stopInterval(a.id));
        await flush();
      } else {
        if (!await flush()) return;
        if (c.focus?.id == a.id) {
          await c.run(() => c.activityRepository!.startInterval(a.id));
        }
      }
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<bool> flush() async {
    try {
      await widget.flushInput();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar el resultado. Conserva el texto y vuelve a intentarlo.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> finish() async {
    final a = c.focus;
    if (a == null || a.running != null || acting) return;
    setState(() => acting = true);
    try {
      if (!await flush()) return;
      if (!mounted) return;
      final end = await showDialog<DateTime>(
        context: context,
        builder: (_) => ActivityEndDialog(initial: c.now()),
      );
      if (end == null || !mounted || c.focus?.id != a.id) return;
      final conflict =
          end.isBefore(a.createdAt) ||
          end.isAfter(c.now()) ||
          a.intervals.any((i) => i.endedAt != null && end.isBefore(i.endedAt!));
      var accept = false;
      if (conflict) {
        accept =
            await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('Revisar hora'),
                    content: const Text(
                      'La hora elegida no coincide con los registros. ¿Guardar esa hora y conservarlos?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Volver'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Guardar esa hora'),
                      ),
                    ],
                  ),
            ) ??
            false;
        if (!accept) return;
      }
      await c.run(
        () => c.activityRepository!.finishActivity(
          a.id,
          end,
          acceptConflicts: accept,
        ),
      );
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> choose() async {
    if (!widget.aiReady) return;
    if (!await flush()) return;
    if (!mounted) return;
    final choice = await showModalBottomSheet<ActivityChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ActivityChooser(controller: c),
    );
    if (choice != null) {
      await c.run(() async {
        await c.activityRepository!.prepareActivity(
          choice.definition,
          exerciseId: choice.exerciseId,
        );
      });
    }
  }

  Future<void> changePreparation() async {
    final a = c.focus;
    if (a == null || a.intervals.isNotEmpty || !await flush()) return;
    if (!mounted || !widget.aiReady) return;
    final choice = await showModalBottomSheet<ActivityChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ActivityChooser(controller: c),
    );
    if (choice == null || c.focus?.id != a.id) return;
    await c.run(
      () => c.activityRepository!.replaceActivityPreparation(
        a.id,
        choice.definition,
        exerciseId: choice.exerciseId,
      ),
    );
  }

  Future<void> rename() async {
    final a = c.focus;
    if (a == null || acting || c.busy) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ActivityNameDialog(initial: a.definition.name),
    );
    if (name == null || c.focus?.id != a.id) return;
    await c.run(() => c.activityRepository!.renameActivity(a.id, name));
  }

  Future<void> rest() async {
    final a = resting ?? c.focus;
    if (a == null) return;
    final value = await showDialog<int>(
      context: context,
      builder: (_) => ActivityRestDialog(seconds: a.definition.restSeconds),
    );
    if (value != null) {
      await c.run(() => c.activityRepository!.setActivityRest(a.id, value));
    }
  }

  Future<void> closeDay() async {
    if (!await flush()) return;
    final workout = c.active;
    if (mounted && workout != null && c.focus == null) {
      await finishSession(context, c, workout, title: 'Finalizar día');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final a = c.focus;
      final running = a?.running;
      final compact = widget.compact;
      final enabled =
          c.loaded && !c.busy && !acting && c.activityRepository != null;
      final restOwner = resting;
      final remaining =
          restOwner?.restEndsAt?.difference(c.now()).inSeconds.clamp(0, 1800) ??
          0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('rename-activity'),
                    onTap: enabled && a != null ? rename : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              a?.definition.name ?? 'Sin actividad',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color:
                                a == null
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant
                                    : null,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('change-activity'),
                  tooltip: 'Elegir otra actividad',
                  onPressed:
                      enabled &&
                              widget.aiReady &&
                              a != null &&
                              a.intervals.isEmpty
                          ? changePreparation
                          : null,
                  icon: const Icon(Icons.swap_horiz),
                ),
                TextButton(
                  key: const Key('finish-activity'),
                  onPressed:
                      enabled &&
                              running == null &&
                              a != null &&
                              a.intervals.isNotEmpty
                          ? finish
                          : null,
                  child: const Text('Terminar'),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    a == null
                        ? 'Esperando actividad'
                        : running != null
                        ? a.definition.repeated
                            ? 'Serie ${a.intervals.length}'
                            : 'En marcha'
                        : a.intervals.isEmpty
                        ? 'Listo'
                        : 'Descanso',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (running != null)
                  Text(
                    _clock(
                      c
                          .now()
                          .difference(running.startedAt)
                          .inSeconds
                          .clamp(0, 8640000),
                    ),
                    key: const Key('activity-clock'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (running == null)
                  TextButton(
                    key: const Key('activity-rest'),
                    onPressed:
                        enabled && (a != null || restOwner != null)
                            ? rest
                            : null,
                    child: Text(
                      restOwner == null
                          ? a == null
                              ? '—'
                              : '${a.definition.restSeconds}s'
                          : '${_clock(remaining)} · ${restOwner.definition.restSeconds}s',
                    ),
                  ),
              ],
            ),
            if (!widget.hideStart || running != null)
              if (compact)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('activity-start-stop'),
                    onPressed:
                        enabled &&
                                a != null &&
                                (running != null || widget.aiReady)
                            ? act
                            : null,
                    icon: Icon(running == null ? Icons.play_arrow : Icons.stop),
                    label: Text(running == null ? 'Iniciar' : 'Parar'),
                  ),
                )
              else
                Align(
                  alignment: Alignment.center,
                  child: SizedBox.square(
                    dimension: compact ? 48 : 108,
                    child: FilledButton(
                      key: const Key('activity-start-stop'),
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed:
                          enabled &&
                                  a != null &&
                                  (running != null || widget.aiReady)
                              ? act
                              : null,
                      child:
                          compact
                              ? Icon(
                                running == null ? Icons.play_arrow : Icons.stop,
                                semanticLabel:
                                    running == null ? 'Iniciar' : 'Parar',
                                size: 24,
                              )
                              : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    running == null
                                        ? Icons.play_arrow
                                        : Icons.stop,
                                    size: compact ? 24 : 36,
                                  ),
                                  Text(running == null ? 'Iniciar' : 'Parar'),
                                ],
                              ),
                    ),
                  ),
                ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  c.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    },
  );
}

String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class ActivityNameDialog extends StatefulWidget {
  const ActivityNameDialog({super.key, required this.initial});
  final String initial;
  @override
  State<ActivityNameDialog> createState() => _ActivityNameDialogState();
}

class _ActivityNameDialogState extends State<ActivityNameDialog> {
  late final input = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void save() {
    try {
      Navigator.pop(context, validName(input.text));
    } on ValidationException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nombre de la actividad'),
    content: TextField(
      key: const Key('activity-name-input'),
      controller: input,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(labelText: 'Nombre', errorText: error),
      onSubmitted: (_) => save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: save, child: const Text('Guardar nombre')),
    ],
  );
}

ActivityDefinition _legacyStrength(
  String name,
  int restSeconds, {
  String instructions = '',
}) => ActivityDefinition(
  name: name,
  restSeconds: restSeconds,
  instructions: instructions,
  fields: const [
    {'key': 'weight_kg', 'label': 'Peso', 'unit': 'kg'},
    {'key': 'reps', 'label': 'Repeticiones', 'unit': ''},
    {'key': 'failure', 'label': 'Fallo', 'unit': ''},
  ],
);

class ActivityChoice {
  const ActivityChoice(this.definition, [this.exerciseId]);
  final ActivityDefinition definition;
  final String? exerciseId;
}

class ActivityChooser extends StatelessWidget {
  const ActivityChooser({super.key, required this.controller});
  final WorkoutController controller;
  @override
  Widget build(BuildContext context) {
    final unique = <String, ActivityDefinition>{};
    for (final a in controller.activities) {
      unique.putIfAbsent(a.definition.name.toLowerCase(), () => a.definition);
    }
    for (final w in controller.history) {
      for (final e in w.exercises) {
        unique.putIfAbsent(
          e.name.toLowerCase(),
          () => _legacyStrength(e.name, e.restSeconds),
        );
      }
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '¿Qué vas a hacer?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final e in controller.active?.exercises ?? <Exercise>[])
                    ListTile(
                      title: Text(e.name),
                      subtitle: Text(
                        e.targetSets == null
                            ? 'Del entrenamiento actual'
                            : '${e.sets.length + controller.activities.where((a) => a.exerciseId == e.id).fold<int>(0, (n, a) => n + a.intervals.where((i) => i.endedAt != null).length)}/${e.targetSets} series · ${e.repsMin}–${e.repsMax} reps',
                      ),
                      onTap:
                          () => Navigator.pop(
                            context,
                            ActivityChoice(
                              ActivityDefinition(
                                name: e.name,
                                restSeconds: e.restSeconds,
                                fields: const [
                                  {
                                    'key': 'weight_kg',
                                    'label': 'Peso',
                                    'unit': 'kg',
                                  },
                                  {
                                    'key': 'reps',
                                    'label': 'Repeticiones',
                                    'unit': '',
                                  },
                                  {
                                    'key': 'failure',
                                    'label': 'Fallo',
                                    'unit': '',
                                  },
                                ],
                              ),
                              e.id,
                            ),
                          ),
                    ),
                  for (final d in unique.values)
                    ListTile(
                      title: Text(d.name),
                      subtitle: const Text('Volver a hacer'),
                      onTap: () => Navigator.pop(context, ActivityChoice(d)),
                    ),
                  for (final routine in controller.routines)
                    for (final e in routine.exercises)
                      ListTile(
                        title: Text(e.name),
                        subtitle: Text(
                          '${routine.name} · ${e.targetSets} series',
                        ),
                        onTap:
                            () => Navigator.pop(
                              context,
                              ActivityChoice(
                                _legacyStrength(
                                  e.name,
                                  e.restSeconds,
                                  instructions:
                                      'De la rutina ${routine.name}: ${e.targetSets} series, ${e.repsMin}–${e.repsMax} repeticiones previstas. No son resultados realizados.',
                                ),
                              ),
                            ),
                      ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Nueva actividad'),
                    onTap: () async {
                      final d = await showDialog<ActivityDefinition>(
                        context: context,
                        builder: (_) => const NewActivityDialog(),
                      );
                      if (context.mounted && d != null) {
                        Navigator.pop(context, ActivityChoice(d));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NewActivityDialog extends StatefulWidget {
  const NewActivityDialog({super.key});
  @override
  State<NewActivityDialog> createState() => _NewActivityDialogState();
}

class _NewActivityDialogState extends State<NewActivityDialog> {
  final name = TextEditingController();
  final seconds = TextEditingController(text: '90');
  bool repeated = true;
  String? error;
  @override
  void dispose() {
    name.dispose();
    seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva actividad'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('activity-name'),
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Varias series o tramos'),
            value: repeated,
            onChanged: (v) => setState(() => repeated = v),
          ),
          TextField(
            controller: seconds,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Descanso (segundos)'),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          try {
            Navigator.pop(
              context,
              ActivityDefinition(
                name: name.text.trim(),
                repeated: repeated,
                restSeconds: int.tryParse(seconds.text) ?? -1,
              ),
            );
          } on ValidationException catch (e) {
            setState(() => error = e.message);
          }
        },
        child: const Text('Preparar'),
      ),
    ],
  );
}

class ActivityRestDialog extends StatefulWidget {
  const ActivityRestDialog({super.key, required this.seconds});
  final int seconds;
  @override
  State<ActivityRestDialog> createState() => _ActivityRestDialogState();
}

class _ActivityRestDialogState extends State<ActivityRestDialog> {
  late final input = TextEditingController(text: '${widget.seconds}');
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Descanso'),
    content: TextField(
      controller: input,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'Segundos', errorText: error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final value = int.tryParse(input.text);
          if (value == null || value < 0 || value > 1800) {
            setState(() => error = 'Entre 0 y 1800');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('Guardar'),
      ),
    ],
  );
}

class ActivityEndDialog extends StatefulWidget {
  const ActivityEndDialog({super.key, required this.initial});
  final DateTime initial;
  @override
  State<ActivityEndDialog> createState() => _ActivityEndDialogState();
}

class _ActivityEndDialogState extends State<ActivityEndDialog> {
  late DateTime end = widget.initial.toLocal();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Terminar actividad'),
    content: Row(
      children: [
        Expanded(
          flex: 3,
          child: InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: end,
                firstDate: DateTime(1970),
                lastDate: DateTime(2100, 12, 31),
              );
              if (date != null && mounted) {
                setState(
                  () =>
                      end = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        end.hour,
                        end.minute,
                        end.second,
                      ),
                );
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha'),
              child: Text(DateFormat('d/M/yyyy').format(end)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(end),
                initialEntryMode: TimePickerEntryMode.input,
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
              );
              if (time != null && mounted) {
                setState(
                  () =>
                      end = DateTime(
                        end.year,
                        end.month,
                        end.day,
                        time.hour,
                        time.minute,
                      ),
                );
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Hora'),
              child: Text(DateFormat('HH:mm').format(end)),
            ),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, end),
        child: const Text('Guardar'),
      ),
    ],
  );
}
