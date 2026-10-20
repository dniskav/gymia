import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/ai_stream_response.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  test('Responses text excludes reasoning and requires completed output', () {
    final stream = AiStreamResponse(AiProtocol.responses);
    stream.add({'type': 'response.reasoning_text.delta', 'delta': 'private'});
    stream.add({'type': 'response.output_text.delta', 'delta': 'Hola'});
    expect(stream.text, 'Hola');
    expect(stream.response, throwsA(isA<ValidationException>()));
    stream.add({
      'type': 'response.completed',
      'response': {'status': 'completed'},
    });
    expect(stream.response()['status'], 'completed');
  });
  test(
    'Anthropic excludes thinking and refuses output stopped by a token limit',
    () {
      final stream = AiStreamResponse(AiProtocol.anthropic);
      stream.add({
        'type': 'content_block_delta',
        'delta': {'type': 'thinking_delta', 'thinking': 'private'},
      });
      stream.add({
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': 'Hola'},
      });
      expect(stream.text, 'Hola');
      expect(
        () => stream.add({
          'type': 'message_delta',
          'delta': {'stop_reason': 'max_tokens'},
        }),
        throwsA(isA<ValidationException>()),
      );
      final valid = AiStreamResponse(AiProtocol.anthropic);
      valid.add({
        'type': 'content_block_delta',
        'delta': {'type': 'text_delta', 'text': 'Listo'},
      });
      valid.add({
        'type': 'message_delta',
        'delta': {'stop_reason': 'end_turn'},
      });
      valid.add({'type': 'message_stop'});
      expect(valid.response()['content'], [
        {'type': 'text', 'text': 'Listo'},
      ]);
    },
  );
  test('Gemini ignores thought parts and only accepts an explicit STOP', () {
    final stream = AiStreamResponse(AiProtocol.gemini);
    stream.add({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'private', 'thought': true},
              {'text': 'Hola'},
            ],
          },
        },
      ],
    });
    stream.add({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': ' mundo'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    });
    expect(stream.text, 'Hola mundo');
    expect(stream.complete, isTrue);
    expect(
      () => AiStreamResponse(AiProtocol.gemini).add({
        'candidates': [
          {'finishReason': 'MAX_TOKENS'},
        ],
      }),
      throwsA(isA<ValidationException>()),
    );
  });
}
