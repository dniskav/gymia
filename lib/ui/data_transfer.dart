import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../application/workout_controller.dart';
import '../domain/transfer.dart';
import '../domain/transfer_repository.dart';
import '../domain/workout.dart';
import 'theme.dart';
import 'google_sheets_import.dart';
import '../domain/sheet_context.dart';
import '../data/sheet_context_store.dart';
import 'package:uuid/uuid.dart';

Future<void> pickSheetForChat(
  BuildContext context,
  WorkoutController controller,
) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final file = await const MethodChannel(
        'com.gymia.app/import',
      ).invokeMapMethod<String, dynamic>('pickSheet');
      if (file == null || !context.mounted) return;
      final bytes = file['bytes'];
      if (bytes is! Uint8List) {
        throw const ValidationException('No se pudo leer la hoja.');
      }
      await openImportDocument(
        context,
        controller,
        bytes,
        name: file['name'] as String? ?? 'Hoja cargada',
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || !context.mounted) return;
      final file = result.files.single;
      if (file.size > 20 * 1024 * 1024) {
        throw const ValidationException('La hoja supera 20 MB.');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      if (context.mounted) {
        await openImportDocument(context, controller, bytes, name: file.name);
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ValidationException
                ? e.message
                : 'No se pudo cargar la hoja. Vuelve a intentarlo.',
          ),
        ),
      );
    }
  }
}

Future<void> openImportDocument(
  BuildContext context,
  WorkoutController controller,
  Uint8List bytes, {
  String name = 'Hoja cargada',
}) async {
  final tabs = SheetDocument.decodeCells(bytes);
  var selected = tabs.keys.first;
  if (tabs.length > 1) {
    final choice = await showDialog<String>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: const Text('Elige la pestaña con tus entrenamientos'),
            children: [
              for (final name in tabs.keys)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, name),
                  child: Text(name),
                ),
            ],
          ),
    );
    if (choice == null) return;
    selected = choice;
  }
  if (!context.mounted) return;
  final sheet = SheetContext(
    id: const Uuid().v4(),
    name: name,
    title: selected,
    loadedAt: DateTime.now(),
    rows: tabs[selected]!,
    source: 'file',
  );
  final confirmed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => SheetContextPreviewScreen(sheet: sheet, loadOnly: true),
    ),
  );
  if (confirmed == true) {
    await SheetContextStore(profileId: controller.profileId).save(sheet);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hoja cargada. Pendiente de interpretación por la IA.'),
        ),
      );
    }
  }
}

class DataTransferScreen extends StatefulWidget {
  const DataTransferScreen({super.key, required this.controller});
  final WorkoutController controller;
  @override
  State<DataTransferScreen> createState() => _DataTransferScreenState();
}

class _DataTransferScreenState extends State<DataTransferScreen> {
  bool working = false;
  TransferRepository get store =>
      widget.controller.repository as TransferRepository;

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<String?> pickText(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > 20 * 1024 * 1024) {
      throw const ValidationException('El archivo supera 20 MB.');
    }
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    return utf8.decode(bytes);
  }

  Future<void> run(Future<void> Function() action) async {
    if (working) return;
    setState(() => working = true);
    try {
      await action();
    } on ValidationException catch (e) {
      message(e.message);
    } on PlatformException catch (e) {
      message(e.message ?? 'No se pudo leer la hoja seleccionada.');
    } catch (_) {
      message('No se pudo leer o compartir el archivo.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> exportBackup() => run(() async {
    final json = await store.createBackupJson();
    final folder = await getTemporaryDirectory();
    final file = File(
      p.join(
        folder.path,
        'gymia-copia-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json',
      ),
    );
    await file.writeAsString(json, flush: true);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Copia de seguridad GymIA',
      text: 'Guarda este archivo en Drive o en un lugar seguro.',
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  });

  Future<void> restoreBackup() => run(() async {
    final source = await pickText(['json']);
    if (source == null || !mounted) return;
    final summary = store.inspectBackupJson(source);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('¿Restaurar esta copia?'),
            content: Text(
              'Contiene ${summary.workouts} ${summary.workouts == 1 ? 'sesión' : 'sesiones'} y ${summary.routines} ${summary.routines == 1 ? 'rutina' : 'rutinas'}${summary.active ? ', incluida una sesión en curso' : ''}. Sustituirá todos los datos que hay ahora en este teléfono. Guarda antes una copia actual si quieres conservarlos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restaurar'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    final ok = await widget.controller.run(
      () => store.restoreBackupJson(source),
    );
    if (ok) message('Copia restaurada. Sesiones y rutinas actualizadas.');
  });

  Future<void> importFile() => run(() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final file = await const MethodChannel(
        'com.gymia.app/import',
      ).invokeMapMethod<String, dynamic>('pickSheet');
      if (file == null || !mounted) return;
      final bytes = file['bytes'];
      if (bytes is! Uint8List) {
        throw const ValidationException(
          'No se pudo leer la hoja seleccionada.',
        );
      }
      await openImportDocument(
        context,
        widget.controller,
        bytes,
        name: file['name'] as String? ?? 'Hoja cargada',
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.size > 20 * 1024 * 1024) {
      throw const ValidationException('La hoja supera 20 MB.');
    }
    if (file.bytes == null && file.path == null) {
      throw const ValidationException(
        'No se pudo leer esa hoja. En Google Sheets usa «Enviar una copia» como Excel o CSV y elige GymIA.',
      );
    }
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    if (!mounted) return;
    await openImportDocument(
      context,
      widget.controller,
      bytes,
      name: file.name,
    );
  });

  Future<void> importGoogleSheets() async {
    if (working) return;
    final sheet = await Navigator.of(context).push<SheetContext>(
      MaterialPageRoute<SheetContext>(
        builder:
            (_) => GoogleSheetsImportScreen(
              controller: widget.controller,
              forAssistant: true,
              loadOnly: true,
            ),
      ),
    );
    if (sheet != null) {
      await run(() async {
        await SheetContextStore(
          profileId: widget.controller.profileId,
        ).save(sheet);
        message('Hoja cargada. Pendiente de interpretación por la IA.');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tus datos')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Tu historial, bajo tu control',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'Guarda una copia fuera de este móvil para recuperarla o pasarla a otro teléfono.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copia de seguridad',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Incluye historial, rutinas y sesión en curso.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: working ? null : exportBackup,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Crear y compartir copia'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: working ? null : restoreBackup,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restaurar copia'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Histórico de Google Sheets',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  defaultTargetPlatform == TargetPlatform.android
                      ? 'Carga tu hoja y pestaña con autorización de Google, o elige una copia Excel o CSV. Se conservan las celdas originales; la IA podrá interpretar tu formato cuando esté conectada.'
                      : 'Carga una copia Excel o CSV. Se conservan las celdas originales, pendientes de interpretación por la IA.',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                if (defaultTargetPlatform == TargetPlatform.android) ...[
                  FilledButton.icon(
                    onPressed: working ? null : importGoogleSheets,
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Importar desde Google Sheets'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: working ? null : importFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(
                    defaultTargetPlatform == TargetPlatform.android
                        ? 'Elegir archivo del móvil o Drive'
                        : 'Elegir copia XLSX o CSV',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (working)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    ),
  );
}

class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({
    super.key,
    required this.controller,
    required this.sheet,
  });
  final WorkoutController controller;
  final CsvSheet sheet;
  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  late CsvMapping mapping = widget.sheet.suggestedMapping();
  CsvPreview? preview;
  Set<String> existing = {};
  bool busy = false;
  String? error;

  Widget workoutTile(ImportedWorkout workout) => Card(
    child: ExpansionTile(
      title: Text(workout.name),
      subtitle: Text(
        '${DateFormat('d/M/yyyy HH:mm').format(workout.date)} · ${workout.exercises.length} ejercicios · ${workout.setCount} series',
      ),
      trailing:
          existing.contains(importedFingerprint(workout))
              ? const Icon(Icons.check_circle_outline_rounded, color: muted)
              : null,
      children: [
        for (final exercise in workout.exercises)
          ListTile(
            title: Text(exercise.name),
            subtitle: Text(
              exercise.sets
                  .map((s) => '${formatWeight(s.weight)} kg × ${s.reps}')
                  .join(' · '),
            ),
          ),
      ],
    ),
  );

  void showAll(String title, Widget Function(int) itemBuilder, int count) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                itemCount: count,
                itemBuilder: (context, i) => itemBuilder(i),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  void change({
    int? date,
    int? exercise,
    int? weight,
    int? reps,
    int? session,
    bool sessionChanged = false,
  }) {
    setState(() {
      mapping = CsvMapping(
        date: date ?? mapping.date,
        exercise: exercise ?? mapping.exercise,
        weight: weight ?? mapping.weight,
        reps: reps ?? mapping.reps,
        session:
            sessionChanged ? (session == -1 ? null : session) : mapping.session,
      );
      preview = null;
      error = null;
    });
  }

  Widget selector(
    String label,
    int value,
    void Function(int) onChanged, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: [
        DropdownMenuItem(
          value: -1,
          child: Text(
            optional ? 'Sin columna · Entrenamiento' : 'Elegir columna',
          ),
        ),
        for (var i = 0; i < widget.sheet.headers.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(
              '${i + 1}. ${widget.sheet.headers[i]}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );

  Future<void> review() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = widget.sheet.preview(mapping);
      final fingerprints =
          await (widget.controller.repository as TransferRepository)
              .existingFingerprints();
      if (mounted) {
        setState(() {
          preview = result;
          existing = fingerprints;
        });
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo revisar el CSV.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    if (busy || preview == null) return;
    final ready =
        preview!.workouts
            .where((w) => !existing.contains(importedFingerprint(w)))
            .toList();
    if (ready.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('¿Importar estas sesiones?'),
            content: Text(
              'Se añadirán ${ready.length} ${ready.length == 1 ? 'sesión' : 'sesiones'} con ${ready.fold<int>(0, (n, w) => n + w.setCount)} series. Filas omitidas por error: ${preview!.errors.length}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Importar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    ImportSummary? summary;
    final ok = await widget.controller.run(() async {
      summary = await (widget.controller.repository as TransferRepository)
          .importWorkouts(preview!.workouts);
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${summary!.added} ${summary!.added == 1 ? 'sesión importada' : 'sesiones importadas'} · ${summary!.duplicates} ${summary!.duplicates == 1 ? 'duplicada omitida' : 'duplicadas omitidas'}.',
          ),
        ),
      );
      Navigator.pop(context);
    } else {
      setState(() => error = widget.controller.error ?? 'No se pudo importar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final duplicateCount =
        preview?.workouts
            .where((w) => existing.contains(importedFingerprint(w)))
            .length ??
        0;
    final newCount = (preview?.workouts.length ?? 0) - duplicateCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar hoja')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${widget.sheet.rows.length} filas encontradas',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Asocia las columnas de tu hoja. Una fila representa una serie.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          selector('Fecha', mapping.date, (v) => change(date: v)),
          selector(
            'Sesión (opcional)',
            mapping.session ?? -1,
            (v) => change(session: v, sessionChanged: true),
            optional: true,
          ),
          selector('Ejercicio', mapping.exercise, (v) => change(exercise: v)),
          selector('Peso (kg)', mapping.weight, (v) => change(weight: v)),
          selector('Repeticiones', mapping.reps, (v) => change(reps: v)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : review,
            child: const Text('Revisar importación'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (preview != null) ...[
            const SizedBox(height: 28),
            Text(
              '$newCount ${newCount == 1 ? 'sesión nueva' : 'sesiones nuevas'} · $duplicateCount ${duplicateCount == 1 ? 'duplicada' : 'duplicadas'} · ${preview!.errors.length} ${preview!.errors.length == 1 ? 'fila con error' : 'filas con errores'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${preview!.validRows} series válidas de ${preview!.totalRows} filas.',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            for (final w in preview!.workouts.take(10)) workoutTile(w),
            if (preview!.workouts.length > 10)
              TextButton(
                onPressed:
                    () => showAll(
                      'Todas las sesiones',
                      (i) => workoutTile(preview!.workouts[i]),
                      preview!.workouts.length,
                    ),
                child: Text('Ver las ${preview!.workouts.length} sesiones'),
              ),
            for (final issue in preview!.errors.take(15))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  issue,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            if (preview!.errors.length > 15)
              TextButton(
                onPressed:
                    () => showAll(
                      'Filas con errores',
                      (i) => Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(preview!.errors[i]),
                      ),
                      preview!.errors.length,
                    ),
                child: Text('Ver los ${preview!.errors.length} errores'),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy || newCount == 0 ? null : import,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Importar sesiones nuevas'),
            ),
          ],
        ],
      ),
    );
  }
}
