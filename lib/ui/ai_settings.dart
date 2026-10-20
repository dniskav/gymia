import 'dart:async';
import 'package:flutter/material.dart';
import '../data/ai_client.dart';
import '../data/chatgpt_auth.dart';
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
    this.chatGptAuth,
  });
  final String profileId;
  final ChatGptAuth? chatGptAuth;
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
  late final chatGpt =
      widget.chatGptAuth ?? ChatGptAuth(profileId: widget.profileId);
  List<ChatGptAccount> chatGptAccounts = [];
  String? chatGptClientId;
  ChatGptAccount? get selectedChatGpt =>
      chatGptAccounts.where((a) => a.clientId == chatGptClientId).firstOrNull;
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
      final accounts = await chatGpt.accounts();
      if (!mounted) return;
      setState(() {
        service = config?.service ?? AiService.opencodeGo;
        protocol = config?.protocol ?? service.defaultProtocol;
        base.text = config?.baseUrl ?? service.baseUrl;
        model.text = config?.model ?? '';
        key.text = config?.apiKey ?? '';
        chatGptAccounts = accounts;
        chatGptClientId = config?.chatGptClientId;
      });
    } catch (_) {
      if (mounted) {
        setState(() => status = 'No se pudo leer la configuración guardada.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted &&
        (key.text.trim().isNotEmpty || selectedChatGpt?.canUsePlan == true)) {
      await fetchModels();
    }
  }

  AiConfig config() => AiConfig(
    service: service,
    baseUrl: base.text.trim(),
    model: model.text.trim(),
    protocol: protocol,
    apiKey: service == AiService.chatgpt ? '' : key.text.trim(),
    chatGptClientId: service == AiService.chatgpt ? chatGptClientId : null,
    profileId: widget.profileId,
  );

  Future<void> connectChatGpt({
    bool usePlan = false,
    bool newAccount = false,
  }) async {
    await run(() async {
      final account = await chatGpt.connect(
        clientId: newAccount ? null : chatGptClientId,
        usePlan:
            usePlan || (!newAccount && selectedChatGpt?.canUsePlan == true),
        consent: usePlan,
        newRegistration: newAccount,
      );
      final accounts = await chatGpt.accounts();
      if (!mounted) return;
      setState(() {
        invalidateCatalog();
        model.clear();
        chatGptAccounts = accounts;
        chatGptClientId = account.clientId;
        status =
            account.canUsePlan
                ? 'Cuenta conectada. Elige un modelo y prueba la conexión para usar el asistente.'
                : 'Identidad conectada. Puedes autorizar por separado el uso de tu plan ChatGPT.';
      });
    });
    if (mounted && selectedChatGpt?.canUsePlan == true) await fetchModels();
  }

  Future<void> disconnectChatGpt() => run(() async {
    final id = chatGptClientId;
    if (id == null) return;
    final revoked = await chatGpt.disconnect(id);
    final saved = await store.load();
    if (saved?.usesChatGpt == true && saved?.chatGptClientId == id) {
      await store.delete();
    }
    final accounts = await chatGpt.accounts();
    if (!mounted) return;
    setState(() {
      invalidateCatalog();
      chatGptAccounts = accounts;
      status =
          revoked
              ? 'Sesión ChatGPT desconectada.'
              : 'Sesión desconectada en este móvil. No se confirmó la revocación remota; desconecta GymIA también en los ajustes de ChatGPT.';
    });
  });

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
            service == AiService.chatgpt
                ? 'Modelos disponibles para esta cuenta: ${result.length}. La prueba de conexión confirma el acceso al elegido.'
                : '${result.length} modelos obtenidos del proveedor. La prueba de conexión confirma si tu clave puede usar el elegido.';
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
              service == AiService.chatgpt
                  ? 'No se pudo obtener el catálogo de esta cuenta. Comprueba la conexión e inténtalo de nuevo.'
                  : 'No se pudo obtener el catálogo. Puedes volver a intentarlo o indicar el modelo manualmente.';
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
    unawaited(chatGpt.cancel());
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
          'Conecta ChatGPT o introduce tu propia clave API. Al enviar un mensaje, el proveedor elegido recibe la conversación reciente, los adjuntos enviados y el contexto de entrenamiento. Las credenciales se guardan de forma segura en este móvil y no se incluyen en las copias de entrenamiento.',
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
                    if (s == AiService.chatgpt &&
                        selectedChatGpt?.canUsePlan == true) {
                      unawaited(fetchModels());
                    }
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
        if (service == AiService.chatgpt) ...[
          const Text(
            'Usa tu plan si tu cuenta y espacio son elegibles. El uso consume sus límites compartidos. No da acceso a tus conversaciones de ChatGPT.',
          ),
          if (chatGptAccounts.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('chatgpt-account-$chatGptClientId'),
              value: chatGptClientId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cuenta ChatGPT'),
              items: [
                for (final account in chatGptAccounts)
                  DropdownMenuItem(
                    value: account.clientId,
                    child: Text(account.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged:
                  busy
                      ? null
                      : (id) {
                        setState(() {
                          chatGptClientId = id;
                          invalidateCatalog();
                          model.clear();
                        });
                        if (selectedChatGpt?.canUsePlan == true) {
                          unawaited(fetchModels());
                        }
                      },
            ),
          Text(
            selectedChatGpt?.connected == true
                ? selectedChatGpt!.canUsePlan
                    ? 'Conectada · permiso de uso del plan concedido'
                    : 'Conectada · solo identidad'
                : 'ChatGPT sin conectar',
          ),
          OutlinedButton(
            key: const Key('chatgpt-connect'),
            onPressed: busy ? null : () => connectChatGpt(),
            child: const Text('Continuar con ChatGPT'),
          ),
          if (selectedChatGpt?.connected == true)
            FilledButton(
              key: const Key('chatgpt-enable-plan'),
              onPressed: busy ? null : () => connectChatGpt(usePlan: true),
              child: Text(
                selectedChatGpt!.canUsePlan
                    ? 'Revisar permiso de uso del plan'
                    : 'Autorizar uso de mi plan ChatGPT',
              ),
            ),
          if (chatGptAccounts.isNotEmpty)
            TextButton(
              onPressed: busy ? null : () => connectChatGpt(newAccount: true),
              child: const Text('Añadir otra cuenta o espacio'),
            ),
          TextButton(
            onPressed: busy ? null : () => run(chatGpt.showUsage),
            child: const Text('Ver uso y permisos en ChatGPT'),
          ),
          if (selectedChatGpt?.connected == true)
            TextButton(
              key: const Key('chatgpt-disconnect'),
              onPressed: busy ? null : disconnectChatGpt,
              child: const Text('Desconectar ChatGPT'),
            ),
          if (busy)
            TextButton(
              key: const Key('chatgpt-cancel'),
              onPressed: chatGpt.cancel,
              child: const Text('Cancelar conexión'),
            ),
        ] else
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
        if (service != AiService.chatgpt)
          TextButton(
            onPressed:
                busy ? null : () => setState(() => manualModel = !manualModel),
            child: Text(
              manualModel
                  ? 'Ocultar identificador manual'
                  : 'Introducir modelo manualmente',
            ),
          ),
        if (manualModel && service != AiService.chatgpt)
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
        if (service != AiService.chatgpt)
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
                  decoration: const InputDecoration(
                    labelText: 'URL base HTTPS',
                  ),
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
          child: Text(
            service == AiService.chatgpt
                ? 'Probar conexión · usa mi plan ChatGPT'
                : 'Probar conexión · usa tu API',
          ),
        ),
        if (service != AiService.chatgpt)
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
