import '../domain/ai_config.dart';
import '../domain/workout.dart';

/// Accumulates only visible assistant text. Reasoning and tool arguments are
/// never rendered, and an interrupted stream is not a completed action.
class AiStreamResponse {
  AiStreamResponse(this.protocol);
  final AiProtocol protocol;
  String text = '';
  bool complete = false;

  static const interrupted = ValidationException(
    'El proveedor interrumpió la respuesta. Puedes volver a intentarlo.',
  );

  void done() {
    if (protocol == AiProtocol.chatCompletions) complete = true;
  }

  String parts(List? values) => (values ?? [])
      .whereType<Map>()
      .where((p) => p['thought'] != true && p['text'] is String)
      .map((p) => p['text'] as String)
      .join('');

  void add(Map<String, dynamic> event) {
    if (event['error'] != null || event['type'] == 'error') throw interrupted;
    switch (protocol) {
      case AiProtocol.chatCompletions:
        for (final choice
            in (event['choices'] as List? ?? []).whereType<Map>()) {
          if (choice['index'] != null && choice['index'] != 0) continue;
          final delta = choice['delta'] as Map?;
          final content = delta?['content'];
          if (content is String) text += content;
          if (content is List) text += parts(content);
          final finish = choice['finish_reason'];
          if (finish != null) {
            if (finish != 'stop') throw interrupted;
            complete = true;
          }
        }
      case AiProtocol.responses:
        switch (event['type']) {
          case 'response.output_text.delta':
            if (event['delta'] is String) text += event['delta'] as String;
          case 'response.completed':
            final response = event['response'] as Map?;
            if (response?['status'] == 'incomplete' ||
                response?['status'] == 'failed') {
              throw interrupted;
            }
            final finalText = (response?['output'] as List? ?? [])
                .whereType<Map>()
                .where((m) => m['type'] == 'message')
                .map((m) => parts(m['content'] as List?))
                .join('\n');
            if (finalText.isNotEmpty) text = finalText;
            complete = true;
          case 'response.incomplete':
          case 'response.failed':
            throw interrupted;
        }
      case AiProtocol.anthropic:
        if (event['type'] == 'content_block_start') {
          final block = event['content_block'] as Map?;
          if (block?['type'] == 'text' && block?['text'] is String) {
            text += block!['text'] as String;
          }
        }
        if (event['type'] == 'content_block_delta') {
          final delta = event['delta'] as Map?;
          if (delta?['type'] == 'text_delta' && delta?['text'] is String) {
            text += delta!['text'] as String;
          }
        }
        if (event['type'] == 'message_delta') {
          final reason = (event['delta'] as Map?)?['stop_reason'];
          if (reason != null &&
              !['end_turn', 'stop_sequence'].contains(reason)) {
            throw interrupted;
          }
        }
        if (event['type'] == 'message_stop') complete = true;
      case AiProtocol.gemini:
        final candidates = event['candidates'] as List? ?? [];
        if (candidates.isEmpty) return;
        final candidate = candidates.first as Map;
        text += parts((candidate['content'] as Map?)?['parts'] as List?);
        final reason = candidate['finishReason'];
        if (reason != null) {
          if (reason != 'STOP') throw interrupted;
          complete = true;
        }
    }
  }

  Map<String, dynamic> response() {
    if (!complete || text.trim().isEmpty) throw interrupted;
    return switch (protocol) {
      AiProtocol.chatCompletions => {
        'choices': [
          {
            'message': {'content': text},
          },
        ],
      },
      AiProtocol.responses => {
        'status': 'completed',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
      AiProtocol.anthropic => {
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
      AiProtocol.gemini => {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      },
    };
  }
}
