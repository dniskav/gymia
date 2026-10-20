import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gymia/domain/sheet_context.dart';
import 'package:gymia/domain/workout.dart';
import 'package:gymia/data/sheet_context_store.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'raw exercise rows preserve blanks, failure, partials and unknown reps',
    () async {
      final rows = [
        <String>[],
        ['Fecha', 'Sesión', 'Ejercicio', 'Serie1', 'Serie2', 'Notas'],
        [
          '28/09/2026',
          'Pull',
          'Remo unilateral',
          '25×8F/lado',
          '',
          '9 + 1 parcial; otras reps desconocidas 👋',
        ],
      ];
      final sheet = SheetContext(
        id: 'sheet',
        name: 'Progreso',
        title: 'Registro2026',
        loadedAt: DateTime(2026, 10, 7, 22, 5),
        rows: rows,
      );
      rows[2][3] = 'mutated';
      const store = SheetContextStore();
      await store.save(sheet);
      final restored = (await store.load())!;
      expect(restored.rows[0], isEmpty);
      expect(restored.rows[2][3], '25×8F/lado');
      expect(restored.rows[2][4], '');
      expect(restored.rows[2][5], contains('1 parcial'));
      expect(restored.loadedAt, sheet.loadedAt);
      expect(jsonEncode(restored.toJson()), jsonEncode(sheet.toJson()));
      await store.delete();
      expect(await store.load(), isNull);
    },
  );

  test(
    'empty or oversized tabs fail without truncating existing context',
    () async {
      const store = SheetContextStore();
      final original = SheetContext(
        id: 'a',
        name: 'Hoja',
        title: 'A',
        loadedAt: DateTime(2026),
        rows: [
          ['Original'],
        ],
      );
      await store.save(original);
      expect(
        () => SheetContext(
          id: 'a',
          name: 'Hoja',
          title: 'A',
          loadedAt: DateTime(2026),
          rows: [
            [],
            [' '],
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(
        () => SheetContext(
          id: 'a',
          name: 'Hoja',
          title: 'A',
          loadedAt: DateTime(2026),
          rows: [
            ['👋' * 40000],
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect((await store.load())!.rows, original.rows);
    },
  );
}
