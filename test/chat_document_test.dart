import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/data/ai_client.dart';
import 'package:gymia/domain/ai_config.dart';
import 'package:gymia/domain/transfer.dart';

void main() {
  test(
    'arbitrary CSV and Excel preserve coordinates without force-schema requirements',
    () {
      final csv = SheetDocument.decodeCells(
        Uint8List.fromList(utf8.encode('\nMi plan;\nRodilla;descanso\n;nota')),
      );
      expect(csv['CSV']!.first, ['']);
      expect(csv['CSV']![2], ['Rodilla', 'descanso']);
      final excel = Excel.createExcel();
      excel.tables.clear();
      excel['Personal']
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2))
          .value = TextCellValue('10 min caminando');
      final raw = SheetDocument.decodeCells(
        Uint8List.fromList(excel.encode()!),
      );
      expect(raw['Personal']![2][1], '10 min caminando');
      expect(raw['Personal']![0].every((v) => v.isEmpty), isTrue);
    },
  );

  test(
    'PDF is a document in every protocol and survives stored conversation',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('%PDF-1.4\nexample'));
      final message = AiMessage(
        'user',
        'Mi informe',
        attachment: AiAttachment(
          name: 'informe.pdf',
          mime: 'application/pdf',
          bytes: bytes,
        ),
        recordedAt: DateTime(2026),
      );
      final restored = AiMessage.fromStorage(
        jsonDecode(jsonEncode(message.forStorage())),
      );
      expect(restored.attachment!.bytes, bytes);
      expect(restored.recordedAt, message.recordedAt);
      for (final protocol in AiProtocol.values) {
        final parts = message.forApi(protocol)['content'] as List;
        final document = parts[1] as Map;
        switch (protocol) {
          case AiProtocol.chatCompletions:
            expect(document['type'], 'file');
            expect(document['file']['filename'], 'informe.pdf');
          case AiProtocol.responses:
            expect(document['type'], 'input_file');
            expect(document['filename'], 'informe.pdf');
          case AiProtocol.anthropic:
            expect(document['type'], 'document');
            expect(document['source']['media_type'], 'application/pdf');
          case AiProtocol.gemini:
            expect(document['inlineData']['mimeType'], 'application/pdf');
        }
      }
    },
  );
}
