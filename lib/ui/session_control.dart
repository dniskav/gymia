import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../application/workout_controller.dart';
import '../domain/workout.dart';
import '../data/sheet_sync_service.dart';

/// Session lifecycle is independent of provider availability or chat history.
class SessionControl extends StatelessWidget {
  const SessionControl({
    super.key,
    required this.controller,
    this.enabled = true,
    this.beforeAction,
    this.sheetLabel,
  });

  final WorkoutController controller;
  final bool enabled;
  final Future<void> Function()? beforeAction;
  final String? sheetLabel;

  Future<void> _act(BuildContext context, Workout? active) async {
    if (!enabled || controller.busy || !controller.loaded) return;
    await beforeAction?.call();
    if (!context.mounted) return;
    if (active == null) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => const _SessionNameDialog(),
      );
      if (name == null || !context.mounted) return;
      final ok = await controller.run(() async {
        await controller.repository.start(name);
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Entreno iniciado. Puedes abrir Entrenamiento para registrar.'
                  : controller.error ?? 'No se pudo iniciar el entreno.',
            ),
          ),
        );
      return;
    }

    await finishSession(context, controller, active, sheetLabel: sheetLabel);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final active = controller.active;
      return FilledButton.icon(
        key: const Key('assistant-session'),
        onPressed:
            enabled && controller.loaded && !controller.busy
                ? () => _act(context, active)
                : null,
        icon: Icon(active == null ? Icons.play_arrow : Icons.stop_rounded),
        label: Text(active == null ? 'Iniciar entreno' : 'Finalizar entreno'),
      );
    },
  );
}

Future<void> finishSession(
  BuildContext context,
  WorkoutController controller,
  Workout active, {
  String? sheetLabel,
  String title = 'Finalizar entreno',
}) async {
  if (controller.busy) return;
  final selection = await showDialog<_FinishSelection>(
    context: context,
    builder:
        (_) => _FinishSessionDialog(
          controller: controller,
          workout: active,
          title: title,
        ),
  );
  if (selection == null || !context.mounted) return;
  if (controller.active?.id != active.id) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('La sesión activa ha cambiado. Revísala.')),
    );
    return;
  }
  final ok = await controller.run(
    () => controller.repository.finish(
      active.id,
      finishedAt: selection.end,
      finishTimeSource:
          selection.edited ? FinishTimeSource.user : FinishTimeSource.system,
      acceptTimeConflicts: selection.acceptConflicts,
    ),
  );
  if (!context.mounted) return;
  Map<String, dynamic>? connection;
  try {
    connection =
        await SheetSyncService(profileId: controller.profileId).connection();
  } catch (_) {
    /* Local save already succeeded. */
  }
  final automaticSheet = connection?['automatic'] == true;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? automaticSheet
                  ? 'Entreno guardado en el móvil. El envío a Google Sheets queda pendiente de confirmación.'
                  : 'Entreno guardado en el móvil. Google Sheets no se ha actualizado.'
              : controller.error ?? 'No se pudo finalizar el entreno.',
        ),
      ),
    );
}

class _FinishSelection {
  const _FinishSelection(this.end, this.edited, this.acceptConflicts);
  final DateTime end;
  final bool edited, acceptConflicts;
}

class _FinishSessionDialog extends StatefulWidget {
  const _FinishSessionDialog({
    required this.controller,
    required this.workout,
    this.title = 'Finalizar entreno',
  });
  final WorkoutController controller;
  final Workout workout;
  final String title;
  @override
  State<_FinishSessionDialog> createState() => _FinishSessionDialogState();
}

class _FinishSessionDialogState extends State<_FinishSessionDialog> {
  late DateTime end = widget.controller.now().toLocal();
  bool edited = false, confirming = false;

  Future<void> chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: end,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() {
      end = DateTime(
        date.year,
        date.month,
        date.day,
        end.hour,
        end.minute,
        end.second,
      );
      edited = true;
    });
  }

  Future<void> chooseTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(end),
      initialEntryMode: TimePickerEntryMode.input,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
    );
    if (time == null || !mounted) return;
    setState(() {
      end = DateTime(end.year, end.month, end.day, time.hour, time.minute);
      edited = true;
    });
  }

  Future<void> submit() async {
    if (confirming) return;
    setState(() => confirming = true);
    final current = widget.controller.active;
    final issues = reviewFinishTime(
      current?.id == widget.workout.id ? current! : widget.workout,
      widget.controller.workouts,
      end,
      widget.controller.now(),
      activityEnds:
          widget.controller.activities
              .where((a) => a.workoutId == widget.workout.id)
              .expand((a) => a.intervals)
              .map((i) => i.endedAt)
              .whereType<DateTime>(),
    );
    var accept = false;
    if (issues.isNotEmpty) {
      accept =
          await showDialog<bool>(
            context: context,
            builder:
                (dialogContext) => AlertDialog(
                  title: const Text('Revisar hora de finalización'),
                  content: SingleChildScrollView(
                    child: Text(
                      '${issues.map((i) => i.message).join('\n\n')}\n\n¿Quieres guardar la hora elegida tal cual? Los registros se conservarán para revisarlos después si lo deseas.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Volver y corregir'),
                    ),
                    FilledButton(
                      key: const Key('accept-finish-time'),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Guardar esa hora'),
                    ),
                  ],
                ),
          ) ??
          false;
      if (!mounted) return;
      if (!accept) {
        setState(() => confirming = false);
        return;
      }
    }
    if (mounted) Navigator.pop(context, _FinishSelection(end, edited, accept));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 340,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              key: const Key('change-finish-date'),
              onTap: confirming ? null : chooseDate,
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
              key: const Key('change-finish-time'),
              onTap: confirming ? null : chooseTime,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Hora'),
                child: Text(
                  DateFormat('HH:mm').format(end),
                  key: const Key('finish-time-value'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: confirming ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('confirm-finish-session'),
        onPressed: confirming ? null : submit,
        child: const Text('Guardar'),
      ),
    ],
  );
}

class _SessionNameDialog extends StatefulWidget {
  const _SessionNameDialog();
  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  final name = TextEditingController(text: 'Entrenamiento');
  final form = GlobalKey<FormState>();

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, name.text.trim());
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Iniciar entreno'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: TextFormField(
          key: const Key('session-name'),
          controller: name,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Nombre de la sesión'),
          onFieldSubmitted: (_) => submit(),
          validator: (value) {
            try {
              validName(value ?? '');
              return null;
            } on ValidationException catch (e) {
              return e.message;
            }
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('confirm-start-session'),
        onPressed: submit,
        child: const Text('Iniciar'),
      ),
    ],
  );
}
