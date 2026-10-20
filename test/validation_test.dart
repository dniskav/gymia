import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  test('weights accept comma/dot and roundtrip exactly', () {
    for (final value in [0, 1, 10, 25, 100, 125, 2250, 6255, 999999]) {
      expect(parseWeight(formatWeight(value)), value);
    }
    expect(parseWeight(' 62.5 '), 6250);
  });
  test(
    'weights reject ambiguous, negative, nonfinite and excess precision',
    () {
      for (final text in [
        '',
        '-2',
        '1,000.50',
        '1.111',
        'NaN',
        'Infinity',
        '1e3',
        '10000',
      ]) {
        expect(
          () => parseWeight(text),
          throwsA(isA<ValidationException>()),
          reason: text,
        );
      }
    },
  );
  test('reps are positive bounded integers', () {
    expect(parseReps('12'), 12);
    for (final text in ['0', '-1', '1.5', '1000', '', 'abc']) {
      expect(() => parseReps(text), throwsA(isA<ValidationException>()));
    }
  });
  test('names are trimmed and required', () {
    expect(validName(' Remo '), 'Remo');
    expect(() => validName('  '), throwsA(isA<ValidationException>()));
    expect(() => validName('x' * 81), throwsA(isA<ValidationException>()));
  });
}
