import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/domain/rest_timer.dart';
import 'package:gymia/domain/routine.dart';
import 'package:gymia/domain/workout.dart';

void main() {
  test('countdown rounds up and never displays negative time', () {
    final now = DateTime(2026);
    final timer = RestTimerState(
      workoutId: 'a',
      durationSeconds: 90,
      remainingMs: 90000,
      endsAt: now.add(const Duration(seconds: 90)),
    );
    expect(timer.displayAt(now), '1:30');
    expect(
      timer.displayAt(now.add(const Duration(milliseconds: 89999))),
      '0:01',
    );
    expect(timer.displayAt(now.add(const Duration(seconds: 100))), '0:00');
    expect(timer.runningAt(now.add(const Duration(seconds: 90))), isFalse);
  });
  test('routine bounds and repetition ranges are enforced', () {
    expect(parseTargetSets('30'), 30);
    expect(parseRestSeconds('5'), 5);
    for (final value in ['0', '-1', '31', '1.5']) {
      expect(() => parseTargetSets(value), throwsA(isA<ValidationException>()));
    }
    for (final value in ['0', '4', '1801', 'NaN']) {
      expect(
        () => parseRestSeconds(value),
        throwsA(isA<ValidationException>()),
      );
    }
    expect(
      () =>
          const RoutineExerciseDraft(
            name: 'A',
            repsMin: 12,
            repsMax: 8,
          ).validate(),
      throwsA(isA<ValidationException>()),
    );
    expect(exerciseKey(' PRESS   banca '), 'press banca');
  });
}
