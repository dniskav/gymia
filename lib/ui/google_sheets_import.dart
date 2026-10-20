import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/workout_controller.dart';
import '../domain/transfer.dart';
import '../domain/workout.dart';
import '../domain/sheet_context.dart';
import '../data/profile_store.dart';
import 'accounts.dart';
import 'data_transfer.dart';

class GoogleSheetsImportScreen extends StatefulWidget {
  const GoogleSheetsImportScreen({
    super.key,
    required this.controller,
    this.forAssistant = false,
    this.loadOnly = false,
  });
  final WorkoutController controller;
  final bool forAssistant;
  final bool loadOnly;

  @override
  State<GoogleSheetsImportScreen> createState() =>
      _GoogleSheetsImportScreenState();
}

class _GoogleSheetsImportScreenState extends State<GoogleSheetsImportScreen> {
  static const channel = MethodChannel('com.gymia.app/google-sheets');
  final search = TextEditingController();
  List<Map<String, String>> files = [];
  String? nextPage;
  String? error;
  String query = '';
  String progress = 'Conectando con Google…';
  bool busy = true;
  bool authorized = false;
  bool reconnect = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => connect());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void showError(Object e) {
    if (!mounted) return;
    setState(() {
      error = switch (e) {
        PlatformException p => p.message ?? 'No se pudo conectar con Google.',
        ValidationException v => v.message,
        FormatException f => f.message,
        _ => 'No se pudo leer la hoja. Vuelve a intentarlo.',
      };
      reconnect = e is PlatformException && e.code == 'GOOGLE_AUTH_REQUIRED';
    });
  }

  Future<void> connect({bool chooseAccount = false}) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      authorized = false;
      files = [];
      nextPage = null;
      error = null;
      progress = 'Elige tu cuenta y autoriza la lectura en Google…';
    });
    try {
      if (chooseAccount) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen()));
        return;
      }
      final bool? granted;
      if (widget.controller.profileId == 'local') {
        // Native refuses unscoped reads; retained for legacy channel fixtures.
        granted = await channel.invokeMethod<bool>('authorize');
      } else {
        await ProfileStore.instance.authorizeSheets(
          profileId: widget.controller.profileId,
        );
        granted = true;
      }
      if (!mounted) return;
      if (granted != true) {
        setState(
          () =>
              error =
                  'Google no completó la autorización. Pulsa Conectar con Google para volver a intentarlo; aún no se han cargado tus hojas.',
        );
        return;
      }
      setState(() => authorized = true);
      await loadFiles();
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadFiles({bool more = false}) async {
    setState(() {
      busy = true;
      error = null;
      progress = 'Buscando tus hojas…';
      if (!more) {
        query = search.text.trim();
        files = [];
        nextPage = null;
      }
    });
    try {
      final response = await channel.invokeMapMethod<String, dynamic>('list', {
        'query': query,
        if (widget.controller.profileId != 'local')
          'expectedSubject': ProfileStore.instance.active?.subject,
        if (more) 'pageToken': nextPage,
      });
      if (!mounted || response == null) return;
      final found =
          (response['files'] as List)
              .map(
                (f) => {
                  'id': (f as Map)['id'] as String,
                  'name': f['name'] as String,
                },
              )
              .toList();
      setState(() {
        files.addAll(found.where((f) => !files.any((v) => v['id'] == f['id'])));
        final page = response['nextPageToken'] as String?;
        nextPage = page == null || page.isEmpty ? null : page;
        if (response['incompleteSearch'] == true) {
          error =
              'Google devolvió una búsqueda parcial. Busca la hoja por su nombre.';
        }
      });
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose(Map<String, String> file) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      progress = 'Cargando las pestañas de ${file['name']}…';
    });
    try {
      final tabs = await channel.invokeListMethod<String>('tabs', {
        'id': file['id'],
        if (widget.controller.profileId != 'local')
          'expectedSubject': ProfileStore.instance.active?.subject,
      });
      if (!mounted) return;
      if (tabs == null || tabs.isEmpty) {
        throw const ValidationException(
          'Esta hoja no tiene pestañas disponibles.',
        );
      }
      setState(() => progress = '');
      final title = await showDialog<String>(
        context: context,
        builder:
            (context) => SimpleDialog(
              title: const Text('Elige la pestaña con tus entrenamientos'),
              children: [
                for (final tab in tabs)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, tab),
                    child: Text(tab),
                  ),
              ],
            ),
      );
      if (title == null || !mounted) return;
      setState(() => progress = 'Leyendo $title…');
      final rows = await channel.invokeListMethod<dynamic>('read', {
        'id': file['id'],
        if (widget.controller.profileId != 'local')
          'expectedSubject': ProfileStore.instance.active?.subject,
        'title': title,
      });
      if (!mounted) return;
      final cells = <List<String>>[
        for (final row in rows ?? [])
          [for (final cell in row as List) cell.toString()],
      ];
      if (widget.forAssistant) {
        final snapshot = SheetContext(
          id: file['id']!,
          name: file['name']!,
          title: title,
          loadedAt: DateTime.now(),
          rows: cells,
        );
        setState(() => progress = '');
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder:
                (_) => SheetContextPreviewScreen(
                  sheet: snapshot,
                  loadOnly: widget.loadOnly,
                ),
          ),
        );
        if (confirmed == true && mounted) Navigator.pop(context, snapshot);
        return;
      }
      final sheet = CsvSheet.fromCells(cells);
      setState(() => progress = '');
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) =>
                  CsvImportScreen(controller: widget.controller, sheet: sheet),
        ),
      );
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tus hojas de Google Sheets')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Elige tu hoja de entrenamiento',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          widget.forAssistant
              ? 'Conecta tu cuenta, elige la hoja y su pestaña. Revisa los datos antes de compartirlos con tu asistente.'
              : 'TrackIA usa la autorización de Google para leer tus hojas. Los datos se guardan en este móvil cuando confirmas la importación.',
        ),
        const SizedBox(height: 16),
        if (authorized) ...[
          TextField(
            controller: search,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'Buscar por nombre',
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: busy ? null : () => loadFiles(),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => loadFiles(),
          ),
          const SizedBox(height: 16),
          for (final file in files)
            Card(
              child: ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(file['name']!),
                trailing: const Icon(Icons.chevron_right),
                enabled: !busy,
                onTap: () => choose(file),
              ),
            ),
          if (!busy && error == null && files.isEmpty)
            const Text(
              'No se encontraron hojas. Prueba otro nombre o cambia de cuenta.',
            ),
          if (nextPage != null)
            TextButton(
              onPressed: busy ? null : () => loadFiles(more: true),
              child: const Text('Cargar más hojas'),
            ),
        ],
        if (busy && progress.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          Text(progress, textAlign: TextAlign.center),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (authorized && !reconnect)
            TextButton(
              onPressed: busy ? null : () => loadFiles(),
              child: const Text('Volver a cargar las hojas'),
            ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: busy ? null : () => connect(chooseAccount: authorized),
          icon: const Icon(Icons.account_circle_outlined),
          label: Text(
            authorized
                ? 'Cambiar cuenta o autorizar de nuevo'
                : 'Conectar con Google',
          ),
        ),
      ],
    ),
  );
}

class SheetContextPreviewScreen extends StatelessWidget {
  const SheetContextPreviewScreen({
    super.key,
    required this.sheet,
    this.loadOnly = false,
  });
  final SheetContext sheet;
  final bool loadOnly;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revisar hoja')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${sheet.name} · ${sheet.title}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          '${sheet.rows.length} filas leídas. Se cargará la pestaña completa; aquí se muestran las primeras 12 filas.',
        ),
        const SizedBox(height: 12),
        Text(
          loadOnly
              ? 'La hoja se guardará en este móvil, pendiente de interpretación. No necesitas IA para cargarla. Cuando esté conectada, podrás pedirle que interprete su estructura. No se crean entrenamientos ni se envían celdas al proveedor al cargar.'
              : 'Al pulsar Cargar y analizar, estas celdas se enviarán al proveedor de IA configurado. Las filas se conservan tal como aparecen, sin convertirlas en entrenamientos.',
        ),
        const SizedBox(height: 12),
        Text(
          sheet.source == 'google'
              ? 'Es una copia de lectura: para traer cambios posteriores usa Actualizar hoja en el chat.'
              : 'Es una copia de lectura del archivo. Para traer cambios, vuelve a cargarlo.',
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < sheet.rows.length && i < 12; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                'Fila ${i + 1}: ${sheet.rows[i].join(' | ')}',
              ),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(loadOnly ? 'Cargar hoja' : 'Cargar y analizar'),
        ),
      ],
    ),
  );
}
