import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/ai_config.dart';
import '../domain/workout.dart';

class AiModelOption {
  const AiModelOption({
    required this.id,
    required this.label,
    this.acceptsImages,
    this.protocol,
  });
  final String id, label;
  final bool? acceptsImages;
  final AiProtocol? protocol;
}

typedef ModelCatalogTransport =
    Future<Map<String, dynamic>> Function(Uri uri, Map<String, String> headers);

class ModelCatalogUnsupportedException extends ValidationException {
  const ModelCatalogUnsupportedException()
    : super(
        'Esta API no ofrece una lista de modelos. Verifica la conexión del modelo indicado.',
      );
}

/// Catalogs come from the selected endpoint. No embedded list of model IDs.
/// Listing is separate from inference and never sends training/chat contents.
class AiModelCatalog {
  AiModelCatalog({ModelCatalogTransport? transport})
    : _transport = transport ?? _get;
  final ModelCatalogTransport _transport;

  Future<List<AiModelOption>> list(AiConfig config) async {
    config.validate(requireModel: false);
    final nativeAnthropic =
        config.service == AiService.anthropic ||
        (config.service == AiService.custom &&
            config.protocol == AiProtocol.anthropic);
    final nativeGemini =
        config.service == AiService.gemini ||
        (config.service == AiService.custom &&
            config.protocol == AiProtocol.gemini);
    final endpoint = Uri.parse(
      '${config.baseUrl.replaceFirst(RegExp(r'/+$'), '')}/models',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'GymIA/0.3.14',
    };
    if (nativeAnthropic) {
      headers['x-api-key'] = config.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (nativeGemini) {
      headers['x-goog-api-key'] = config.apiKey;
    } else {
      headers['Authorization'] = 'Bearer ${config.apiKey}';
    }
    final models = <String, AiModelOption>{};
    final seenCursors = <String>{};
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    String? cursor;
    for (var page = 0; page < 20; page++) {
      if (DateTime.now().isAfter(deadline)) {
        throw const ValidationException(
          'El proveedor tardó demasiado en completar el catálogo. Puedes volver a cargarlo.',
        );
      }
      final query = <String, String>{
        if (nativeAnthropic) 'limit': '1000',
        if (nativeGemini) 'pageSize': '1000',
        if (cursor != null) (nativeGemini ? 'pageToken' : 'after_id'): cursor,
      };
      final response = await _transport(
        query.isEmpty ? endpoint : endpoint.replace(queryParameters: query),
        headers,
      );
      final data = response[nativeGemini ? 'models' : 'data'];
      if (data is! List) {
        throw const ValidationException(
          'El proveedor no devolvió un catálogo de modelos compatible. Puedes indicar el modelo manualmente.',
        );
      }
      for (final raw in data) {
        if (raw is! Map) continue;
        final methods = raw['supportedGenerationMethods'];
        if (nativeGemini &&
            (methods is! List || !methods.contains('generateContent'))) {
          continue;
        }
        final rawId = nativeGemini ? raw['name'] : raw['id'];
        if (rawId is! String) continue;
        final id =
            nativeGemini ? rawId.replaceFirst(RegExp(r'^models/'), '') : rawId;
        if (id.isEmpty || id.length > 200 || id.contains(RegExp(r'\s'))) {
          continue;
        }
        final architecture = raw['architecture'];
        final inputs =
            architecture is Map
                ? architecture['input_modalities']
                : raw['input_modalities'];
        final outputs =
            architecture is Map
                ? architecture['output_modalities']
                : raw['output_modalities'];
        if (outputs is List && !outputs.contains('text')) continue;
        // Some APIs list embeddings/media beside LLMs but give no capabilities.
        if (RegExp(
          r'^(text-embedding|embedding|whisper|tts|dall-e|sora|imagen|veo)(-|/|$)',
          caseSensitive: false,
        ).hasMatch(id)) {
          continue;
        }
        final display =
            raw['display_name'] ?? raw['displayName'] ?? raw['name'];
        final label =
            display is String && display.isNotEmpty && display.length <= 250
                ? display
                : id;
        final declaredEndpoint = raw['endpoint'];
        AiProtocol? protocol;
        if (declaredEndpoint is String) {
          if (declaredEndpoint.endsWith('/chat/completions')) {
            protocol = AiProtocol.chatCompletions;
          }
          if (declaredEndpoint.endsWith('/responses')) {
            protocol = AiProtocol.responses;
          }
          if (declaredEndpoint.endsWith('/messages')) {
            protocol = AiProtocol.anthropic;
          }
          // Only select a known format. Never follow a catalog-provided URL.
        }
        models.putIfAbsent(
          id,
          () => AiModelOption(
            id: id,
            label: label,
            acceptsImages:
                inputs is List
                    ? inputs.contains('image')
                    : raw['supports_image_in'] is bool
                    ? raw['supports_image_in'] as bool
                    : null,
            protocol: protocol,
          ),
        );
      }
      if (models.length > 5000) {
        throw const ValidationException(
          'El catálogo es demasiado grande. Usa un identificador manual.',
        );
      }
      final next =
          nativeGemini
              ? response['nextPageToken']
              : nativeAnthropic && response['has_more'] == true
              ? response['last_id']
              : null;
      if (next == null || next == '') {
        if (models.isEmpty) {
          throw const ValidationException(
            'El proveedor no devolvió modelos de conversación. Puedes indicar uno manualmente.',
          );
        }
        return List<AiModelOption>.unmodifiable(models.values);
      }
      if (next is! String || !seenCursors.add(next)) {
        throw const ValidationException(
          'No se pudo completar la lista de modelos. Puedes volver a cargarla o indicar uno manualmente.',
        );
      }
      cursor = next;
    }
    throw const ValidationException(
      'El catálogo tiene demasiadas páginas. Puedes indicar un modelo manualmente.',
    );
  }

  static Future<Map<String, dynamic>> _get(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client =
        HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        final response = await request.close();
        if (response.statusCode == 404 || response.statusCode == 405) {
          throw const ModelCatalogUnsupportedException();
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ValidationException(switch (response.statusCode) {
            401 => 'El proveedor rechazó la clave al consultar sus modelos.',
            403 =>
              'El proveedor no permite consultar el catálogo con esta clave.',
            404 || 405 =>
              'Esta API no ofrece una lista de modelos compatible. Puedes indicar el modelo manualmente.',
            429 =>
              'El proveedor limita las consultas. Espera y vuelve a cargar los modelos.',
            _ =>
              'No se pudo consultar el catálogo (${response.statusCode}). Puedes volver a intentarlo.',
          });
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) {
            throw const ValidationException(
              'El catálogo supera el tamaño admitido. Puedes usar un modelo manual.',
            );
          }
          bytes.addAll(chunk);
        }
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) throw const FormatException();
        return result;
      })().timeout(const Duration(seconds: 30));
    } on ValidationException {
      rethrow;
    } catch (_) {
      // Never expose server bodies, URLs containing credentials or HTTP errors.
      throw const ValidationException(
        'No se pudo obtener la lista de modelos. Revisa la conexión y vuelve a intentarlo; también puedes indicar el modelo manualmente.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
