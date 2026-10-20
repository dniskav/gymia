import 'workout.dart';

enum AiProtocol { chatCompletions, responses, anthropic, gemini }

enum AiService {
  opencodeGo,
  opencodeZen,
  openai,
  chatgpt,
  anthropic,
  gemini,
  openrouter,
  deepseek,
  minimax,
  kimi,
  custom,
}

extension AiServiceInfo on AiService {
  String get label => switch (this) {
    AiService.opencodeGo => 'OpenCode Go',
    AiService.opencodeZen => 'OpenCode Zen',
    AiService.openai => 'OpenAI',
    AiService.chatgpt => 'ChatGPT · usar mi plan',
    AiService.anthropic => 'Claude / Anthropic',
    AiService.gemini => 'Google Gemini',
    AiService.openrouter => 'OpenRouter',
    AiService.deepseek => 'DeepSeek',
    AiService.minimax => 'MiniMax',
    AiService.kimi => 'Kimi / Moonshot',
    AiService.custom => 'API personalizada',
  };
  String get baseUrl => switch (this) {
    AiService.opencodeGo => 'https://opencode.ai/zen/go/v1',
    AiService.opencodeZen => 'https://opencode.ai/zen/v1',
    AiService.openai || AiService.chatgpt => 'https://api.openai.com/v1',
    AiService.anthropic => 'https://api.anthropic.com/v1',
    AiService.gemini => 'https://generativelanguage.googleapis.com/v1beta',
    AiService.openrouter => 'https://openrouter.ai/api/v1',
    AiService.deepseek => 'https://api.deepseek.com/v1',
    AiService.minimax => 'https://api.minimax.io/v1',
    AiService.kimi => 'https://api.moonshot.ai/v1',
    AiService.custom => '',
  };
  AiProtocol get defaultProtocol => switch (this) {
    AiService.openai || AiService.chatgpt => AiProtocol.responses,
    AiService.anthropic => AiProtocol.anthropic,
    AiService.gemini => AiProtocol.gemini,
    _ => AiProtocol.chatCompletions,
  };

  AiProtocol protocolForModel(String value) {
    if (this != AiService.opencodeGo && this != AiService.opencodeZen) {
      return defaultProtocol;
    }
    final name = value.toLowerCase().trim().replaceFirst(
      RegExp(r'^opencode(?:-go)?/'),
      '',
    );
    if (name.startsWith('gemini-')) return AiProtocol.gemini;
    if (name.startsWith('claude-') ||
        name.startsWith('minimax-') ||
        (name.startsWith('qwen') &&
            !(this == AiService.opencodeZen && name == 'qwen3.8-max'))) {
      return AiProtocol.anthropic;
    }
    if (name.startsWith('gpt-') ||
        name.startsWith('grok-') ||
        name.startsWith('muse-')) {
      return AiProtocol.responses;
    }
    return AiProtocol.chatCompletions;
  }
}

class AiConfig {
  const AiConfig({
    required this.service,
    required this.baseUrl,
    required this.model,
    required this.protocol,
    required this.apiKey,
    this.chatGptClientId,
    this.profileId = 'local',
  });
  final AiService service;
  final String baseUrl, model, apiKey;
  final AiProtocol protocol;
  final String? chatGptClientId;
  final String profileId;
  bool get usesChatGpt => service == AiService.chatgpt;

  String get modelId => switch (service) {
    AiService.opencodeGo => model.replaceFirst(RegExp(r'^opencode-go/'), ''),
    AiService.opencodeZen => model.replaceFirst(RegExp(r'^opencode/'), ''),
    _ => model,
  };

  // GLM-5.3 and GLM-5.3-Flash are distinct models. Z.ai documents
  // only the latter as native multimodal. Unknown models are not blocked.
  String? get imageInputWarning =>
      modelId.toLowerCase().split('/').last == 'glm-5.3'
          ? 'GLM-5.3 admite solo texto. Para imágenes prueba glm-5.3-flash con Chat Completions, o configura otro modelo con visión. Tu mensaje y adjunto se conservan.'
          : null;

  void validate({bool requireModel = true}) {
    if (usesChatGpt &&
        (baseUrl != AiService.chatgpt.baseUrl ||
            protocol != AiProtocol.responses ||
            chatGptClientId == null ||
            chatGptClientId!.isEmpty ||
            apiKey.isNotEmpty)) {
      throw const ValidationException(
        'Conecta tu cuenta de ChatGPT desde ajustes de IA.',
      );
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ValidationException(
        'Introduce la URL base HTTPS de la API, sin claves ni parámetros.',
      );
    }
    if (requireModel &&
        (modelId.trim().isEmpty ||
            model.length > 200 ||
            model.contains(RegExp(r'\s')))) {
      throw const ValidationException(
        'Introduce el identificador exacto del modelo.',
      );
    }
    if (!usesChatGpt &&
        (apiKey.trim().isEmpty || apiKey.contains(RegExp(r'[\r\n]')))) {
      throw const ValidationException('Introduce tu clave API del proveedor.');
    }
  }

  Map<String, dynamic> toJson() => {
    'service': service.name,
    'baseUrl': baseUrl,
    'model': model,
    'protocol': protocol.name,
    'apiKey': apiKey,
    if (usesChatGpt) 'chatGptClientId': chatGptClientId,
    if (usesChatGpt) 'profileId': profileId,
  };
  factory AiConfig.fromJson(Map<String, dynamic> value) => AiConfig(
    service: AiService.values.byName(value['service'] as String),
    baseUrl: value['baseUrl'] as String,
    model: value['model'] as String,
    protocol: AiProtocol.values.byName(value['protocol'] as String),
    apiKey: value['apiKey'] as String,
    chatGptClientId: value['chatGptClientId'] as String?,
    profileId: value['profileId'] as String? ?? 'local',
  );
}
