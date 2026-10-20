import 'package:flutter/material.dart';
import '../application/workout_controller.dart';
import '../domain/routine.dart';
import '../domain/workout.dart';
import 'theme.dart';

class RoutineLibrary extends StatelessWidget {
  const RoutineLibrary({
    super.key,
    required this.controller,
    required this.onStart,
  });
  final WorkoutController controller;
  final void Function(Routine) onStart;

  void _edit(BuildContext context, [Routine? routine]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutineEditor(controller: controller, routine: routine),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Tus rutinas',
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Prepara una vez. Entrena a tu ritmo.',
        style: TextStyle(color: muted, fontSize: 16),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Crear rutina'),
      ),
      const SizedBox(height: 24),
      if (controller.routines.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.view_list_rounded, color: lime, size: 32),
              SizedBox(height: 16),
              Text(
                'Tu próxima sesión, preparada',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Crea, por ejemplo, «Pierna A» con tus ejercicios, series y rango de repeticiones.',
                style: TextStyle(color: muted, height: 1.5),
              ),
            ],
          ),
        ),
      for (final routine in controller.routines)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        routine.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones de ${routine.name}',
                      onSelected: (value) async {
                        if (value == 'edit') {
                          _edit(context, routine);
                          return;
                        }
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder:
                              (ctx) => AlertDialog(
                                title: const Text('¿Eliminar rutina?'),
                                content: Text(
                                  'Se eliminará «${routine.name}». Tus entrenamientos guardados y la sesión en curso se conservarán.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                        );
                        if (confirmed == true) {
                          await controller.run(
                            () =>
                                controller.repository.deleteRoutine(routine.id),
                          );
                        }
                      },
                      itemBuilder:
                          (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar rutina'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar rutina'),
                            ),
                          ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < routine.exercises.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ${routine.exercises[i].name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          routine.exercises[i].description,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => onStart(routine),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      controller.active == null
                          ? 'Entrenar'
                          : 'Continuar sesión activa',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class RoutineEditor extends StatefulWidget {
  const RoutineEditor({super.key, required this.controller, this.routine});
  final WorkoutController controller;
  final Routine? routine;
  @override
  State<RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends State<RoutineEditor> {
  late final name = TextEditingController(text: widget.routine?.name ?? '');
  late final exercises = [...?widget.routine?.exercises];
  final form = GlobalKey<FormState>();
  bool dirty = false, saving = false, leaving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _exit() {
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _close() async {
    if (saving || leaving) return;
    if (!dirty) {
      _exit();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('¿Salir sin guardar?'),
            content: const Text('Los cambios en esta rutina se perderán.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Seguir editando'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar cambios'),
              ),
            ],
          ),
    );
    if (discard == true && mounted) _exit();
  }

  Future<void> _exercise([int? index]) async {
    final result = await showDialog<RoutineExerciseDraft>(
      context: context,
      builder:
          (_) => RoutineExerciseDialog(
            initial: index == null ? null : exercises[index],
          ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          exercises.add(result);
        } else {
          exercises[index] = result;
        }
        dirty = true;
        error = null;
      });
    }
  }

  Future<void> _save() async {
    if (saving) return;
    if (!form.currentState!.validate()) return;
    if (exercises.isEmpty) {
      setState(() => error = 'Añade al menos un ejercicio.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final ok = await widget.controller.run(() async {
      await widget.controller.repository.saveRoutine(
        id: widget.routine?.id,
        name: name.text,
        exercises: exercises,
      );
    });
    if (!mounted) return;
    setState(() {
      saving = false;
      error = widget.controller.error;
    });
    if (ok) _exit();
  }

  void _move(int index, int delta) => setState(() {
    final e = exercises.removeAt(index);
    exercises.insert(index + delta, e);
    dirty = true;
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: saving ? null : _close,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.routine == null ? 'Crear rutina' : 'Editar rutina'),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: saving,
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  key: const Key('routine-name'),
                  controller: name,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la rutina',
                    hintText: 'Ej. Pierna A',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() => dirty = true),
                  validator: (v) {
                    try {
                      validName(v ?? '');
                      return null;
                    } on ValidationException catch (e) {
                      return e.message;
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Define tus objetivos. Las series se registrarán cuando entrenes.',
                  style: TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < exercises.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      key: ValueKey('routine-item-$i'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${exercises[i].name}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            exercises[i].description,
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Subir ejercicio ${i + 1}',
                                onPressed: i == 0 ? null : () => _move(i, -1),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: 'Bajar ejercicio ${i + 1}',
                                onPressed:
                                    i == exercises.length - 1
                                        ? null
                                        : () => _move(i, 1),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              IconButton(
                                tooltip: 'Editar ejercicio ${i + 1}',
                                onPressed: () => _exercise(i),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Quitar ejercicio ${i + 1}',
                                onPressed:
                                    () => setState(() {
                                      exercises.removeAt(i);
                                      dirty = true;
                                    }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: exercises.length >= 50 ? null : () => _exercise(),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir ejercicio a rutina'),
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? 'Guardando…' : 'Guardar rutina'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class RoutineExerciseDialog extends StatefulWidget {
  const RoutineExerciseDialog({super.key, this.initial});
  final RoutineExerciseDraft? initial;
  @override
  State<RoutineExerciseDialog> createState() => _RoutineExerciseDialogState();
}

class _RoutineExerciseDialogState extends State<RoutineExerciseDialog> {
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final sets = TextEditingController(
    text: '${widget.initial?.targetSets ?? 3}',
  );
  late final min = TextEditingController(
    text: '${widget.initial?.repsMin ?? 8}',
  );
  late final max = TextEditingController(
    text: '${widget.initial?.repsMax ?? 12}',
  );
  late final rest = TextEditingController(
    text: '${widget.initial?.restSeconds ?? 90}',
  );
  final form = GlobalKey<FormState>();
  String? error;
  @override
  void dispose() {
    for (final c in [name, sets, min, max, rest]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!form.currentState!.validate()) return;
    final result = RoutineExerciseDraft(
      name: name.text.trim(),
      targetSets: int.parse(sets.text.trim()),
      repsMin: int.parse(min.text.trim()),
      repsMax: int.parse(max.text.trim()),
      restSeconds: int.parse(rest.text.trim()),
    );
    try {
      result.validate();
      Navigator.pop(context, result);
    } on ValidationException catch (e) {
      setState(() => error = e.message);
    }
  }

  Widget number(
    String key,
    String label,
    TextEditingController c,
    int Function(String) parse,
  ) => TextFormField(
    key: Key(key),
    controller: c,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: label, errorMaxLines: 3),
    validator: (v) {
      try {
        parse(v ?? '');
        return null;
      } on ValidationException catch (e) {
        return e.message;
      }
    },
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Ejercicio de rutina' : 'Editar objetivo',
    ),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('routine-exercise-name'),
                controller: name,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Ejercicio',
                  hintText: 'Ej. Sentadilla',
                ),
                validator: (v) {
                  try {
                    validName(v ?? '');
                    return null;
                  } on ValidationException catch (e) {
                    return e.message;
                  }
                },
              ),
              const SizedBox(height: 12),
              number('target-sets', 'Series previstas', sets, parseTargetSets),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: number('reps-min', 'Reps mín.', min, parseReps),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: number('reps-max', 'Reps máx.', max, parseReps),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              number(
                'rest-seconds',
                'Descanso (segundos)',
                rest,
                parseRestSeconds,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar ejercicio')),
    ],
  );
}
