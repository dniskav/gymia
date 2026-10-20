import 'dart:async';
import 'package:flutter/material.dart';
import '../data/ai_client.dart';
import '../data/ai_model_catalog.dart';
import '../data/ai_settings_store.dart';
import '../domain/ai_config.dart';
import '../domain/workout.dart';
import 'package:uuid/uuid.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    super.key,
    this.catalog,
    this.client,
    this.profileId = 'local',
  });
  final String profileId;
  final AiModelCatalog? catalog;
  final AiClient? client;
  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final base = TextEditingController();
  final model = TextEditingController();
  final key = TextEditingController();
  late final store = AiSettingsStore(profileId: widget.profileId);
  AiService service = AiService.opencodeGo;
  AiProtocol protocol = AiProtocol.chatCompletions;
  bool busy = true;
  bool reveal = false;
  String? status;
  String? catalogStatus;
  List<AiModelOption> models = [];
  bool loadingModels = false;
  bool manualModel = false;
  Timer? catalogDebounce;
  int catalogRequest = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final config = await store.load();
      if (!mounted) return;
      setState(() {
        service = config?.service ?? AiService.opencodeGo;
        protocol = config?.protocol ?? service.defaultProtocol;
        base.text = config?.baseUrl ?? service.baseUrl;
        model.text = config?.model ?? '';
        key.text = config?.apiKey ?? '';
      });
    } catch (_) {
      if (mounted) {
        setState(() => status = 'No se pudo leer la configuración guardada.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && key.text.trim().isNotEmpty) await fetchModels();
  }

  AiConfig config() => AiConfig(
    service: service,
    baseUrl: base.text.trim(),
    model: model.text.trim(),
    protocol: protocol,
    apiKey: key.text.trim(),
  );

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
    } on ValidationException catch (e) {
      if (mounted) setState(() => status = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => status = 'No se pudo completar la operación.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void updateModelProtocol(String value) {
    if (service != AiService.opencodeGo && service != AiService.opencodeZen) {
      return;
    }
    setState(() {
      protocol = service.protocolForModel(value);
    });
  }

  void invalidateCatalog() {
    catalogDebounce?.cancel();
    catalogRequest++;
    models = [];
    loadingModels = false;
    catalogStatus = null;
  }

  void keyChanged(String _) {
    setState(invalidateCatalog);
    if (key.text.trim().isEmpty) return;
    catalogDebounce = Timer(const Duration(milliseconds: 900), fetchModels);
  }

  Future<void> fetchModels() async {
    catalogDebounce?.cancel();
    if (busy || !mounted) return;
    final requested = config();
    final ticket = ++catalogRequest;
    setState(() {
      loadingModels = true;
      catalogStatus = null;
    });
    try {
      final result = await (widget.catalog ?? AiModelCatalog()).list(requested);
      if (!mounted || ticket != catalogRequest) return;
      setState(() {
        models = result;
        if (model.text.trim().isEmpty) {
          // A real catalog entry, never a static default ID. Do not replace
          // an existing selection merely because it disappears from the list.
          model.text = result.first.id;
          if (service != AiService.custom) {
            protocol =
                result.first.protocol ??
                service.protocolForModel(result.first.id);
          }
        }
        catalogStatus =
            '${result.length} modelos obtenidos del proveedor. La prueba de conexión confirma si tu clave puede usar el elegido.';
      });
    } on ValidationException catch (e) {
      if (mounted && ticket == catalogRequest) {
        setState(() {
          catalogStatus = e.message;
          manualModel = true;
        });
      }
    } catch (_) {
      if (mounted && ticket == catalogRequest) {
        setState(() {
          catalogStatus =
              'No se pudo obtener el catálogo. Puedes volver a intentarlo o indicar el modelo manualmente.';
          manualModel = true;
        });
      }
    } finally {
      if (mounted && ticket == catalogRequest) {
        setState(() => loadingModels = false);
      }
    }
  }

  @override
  void dispose() {
    catalogDebounce?.cancel();
    catalogRequest++;
    base.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Proveedor de IA')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Conecta tu asistente',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Introduce aquí tu propia clave API. Al enviar un mensaje, el proveedor elegido recibe la conversación reciente y el contexto de entrenamiento mostrado por GymIA. La clave se guarda de forma segura en este móvil y no se incluye en las copias de entrenamiento.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<AiService>(
          value: service,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Proveedor'),
          items: [
            for (final s in AiService.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged:
              busy
                  ? null
                  : (s) {
                    if (s == null) return;
                    setState(() {
                      invalidateCatalog();
                      service = s;
                      protocol = s.defaultProtocol;
                      base.text = s.baseUrl;
                      model.clear();
                      key.clear();
                      status = null;
                      manualModel = false;
                    });
                  },
        ),
        const SizedBox(height: 16),
        if (service == AiService.custom) ...[
          TextField(
            key: const Key('ai-base-url'),
            controller: base,
            enabled: !busy,
            onChanged: (_) => setState(invalidateCatalog),
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'URL base de la API',
              helperText: 'HTTPS, por ejemplo https://tu-proveedor.com/v1',
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('ai-api-key'),
          controller: key,
          enabled: !busy,
          onChanged: keyChanged,
          onSubmitted: (_) => fetchModels(),
          obscureText: !reveal,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Clave API',
            suffixIcon: IconButton(
              tooltip: reveal ? 'Ocultar clave' : 'Mostrar clave',
              onPressed: () => setState(() => reveal = !reveal),
              icon: Icon(reveal ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('ai-load-models'),
          onPressed: busy || loadingModels ? null : fetchModels,
          icon: const Icon(Icons.refresh),
          label: Text(
            loadingModels
                ? 'Consultando modelos…'
                : 'Obtener / actualizar modelos',
          ),
        ),
        if (loadingModels) const LinearProgressIndicator(),
        if (catalogStatus != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(catalogStatus!),
          ),
        if (models.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(
              'catalog-${models.map((m) => m.id).join('|')}-${config().modelId}',
            ),
            value:
                models.any((m) => m.id == config().modelId)
                    ? config().modelId
                    : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Modelo'),
            hint: const Text('Elige un modelo del catálogo'),
            items: [
              for (final m in models)
                DropdownMenuItem(
                  value: m.id,
                  child: Text(
                    m.label == m.id ? m.id : '${m.label} · ${m.id}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged:
                busy
                    ? null
                    : (id) {
                      if (id == null) return;
                      final option = models.singleWhere((m) => m.id == id);
                      setState(() {
                        model.text = id;
                        if (service != AiService.custom) {
                          protocol =
                              option.protocol ?? service.protocolForModel(id);
                        }
                      });
                    },
          ),
        if (model.text.isNotEmpty &&
            !models.any((m) => m.id == config().modelId))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Modelo actual: ${model.text}. Se conserva aunque no aparezca en el catálogo.',
            ),
          ),
        TextButton(
          onPressed:
              busy ? null : () => setState(() => manualModel = !manualModel),
          child: Text(
            manualModel
                ? 'Ocultar identificador manual'
                : 'Introducir modelo manualmente',
          ),
        ),
        if (manualModel)
          TextField(
            key: const Key('ai-model-manual'),
            controller: model,
            enabled: !busy,
            onChanged: (value) {
              updateModelProtocol(value);
              setState(() {});
            },
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Identificador del modelo',
            ),
          ),
        if (service == AiService.opencodeGo) ...[
          const SizedBox(height: 12),
          const Text(
            'Go está orientado a agentes de programación. Esta conexión se identifica como GymIA; comprueba con tu proveedor si admite este uso. No se cambia automáticamente a Zen ni a otro servicio.',
          ),
        ],
        ExpansionTile(
          title: const Text('Configuración de la API'),
          children: [
            if (service != AiService.custom)
              TextField(
                key: const Key('ai-base-url'),
                controller: base,
                enabled: !busy,
                onChanged: (_) => setState(invalidateCatalog),
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'URL base HTTPS'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AiProtocol>(
              value: protocol,
              decoration: const InputDecoration(
                labelText: 'Formato compatible con el modelo',
              ),
              items: [
                for (final p in AiProtocol.values)
                  DropdownMenuItem(
                    value: p,
                    child: Text(switch (p) {
                      AiProtocol.chatCompletions => 'Chat Completions',
                      AiProtocol.responses => 'Responses',
                      AiProtocol.anthropic => 'Anthropic Messages',
                      AiProtocol.gemini => 'Gemini',
                    }),
                  ),
              ],
              onChanged:
                  busy
                      ? null
                      : (p) {
                        if (p != null) {
                          setState(() {
                            invalidateCatalog();
                            protocol = p;
                          });
                        }
                      },
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              busy
                  ? null
                  : () => run(() async {
                    await store.save(config());
                    if (mounted) {
                      setState(() => status = 'Configuración guardada.');
                    }
                  }),
          child: const Text('Guardar proveedor'),
        ),
        OutlinedButton(
          onPressed:
              busy
                  ? null
                  : () => run(() async {
                    final tested = config();
                    final answer = await (widget.client ?? AiClient()).reply(
                      tested,
                      const [
                        AiMessage(
                          'user',
                          'Responde brevemente en español para confirmar que funciona el chat de GymIA.',
                        ),
                      ],
                      system:
                          'Eres el asistente de gimnasio GymIA. Esta solicitud prueba una conexión real de conversación, no una tarea de programación.',
                      sessionId: const Uuid().v4(),
                    );
                    await store.save(tested);
                    await store.markVerified(tested);
                    if (mounted) {
                      setState(
                        () => status = 'El proveedor respondió:\n$answer',
                      );
                    }
                  }),
          child: const Text('Probar conexión · usa tu API'),
        ),
        TextButton(
          onPressed:
              busy
                  ? null
                  : () => run(() async {
                    await store.delete();
                    setState(invalidateCatalog);
                    key.clear();
                    if (mounted) {
                      setState(
                        () => status = 'Configuración y clave eliminadas.',
                      );
                    }
                  }),
          child: const Text('Eliminar configuración y clave'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(status!),
          ),
      ],
    ),
  );
}
