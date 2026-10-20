import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymia/application/workout_controller.dart';
import 'package:gymia/domain/workout.dart';
import 'package:gymia/domain/routine.dart';
import 'package:gymia/domain/rest_timer.dart';
import 'package:gymia/domain/workout_repository.dart';

class ReadRepository extends Fake implements WorkoutRepository {
  @override
  Future<List<Workout>> load() async => [];
  @override
  Future<List<Routine>> loadRoutines() async => [];
  @override
  Future<RestTimerState?> loadRestTimer() async => null;
}

void main() {
  test(
    'ignores a second write while the first is awaiting durable storage',
    () async {
      final controller = WorkoutController(ReadRepository());
      final disk = Completer<void>();
      var writes = 0;
      final first = controller.run(() async {
        writes++;
        await disk.future;
      });
      final second = await controller.run(() async {
        writes++;
      });
      expect(second, isFalse);
      expect(controller.busy, isTrue);
      expect(writes, 1);
      disk.complete();
      expect(await first, isTrue);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );

  test(
    'validation failure is visible and the next operation can recover',
    () async {
      final controller = WorkoutController(ReadRepository());
      final result = await controller.run(() async {
        throw const ValidationException('Registra al menos una serie.');
      });
      expect(result, isFalse);
      expect(controller.error, 'Registra al menos una serie.');
      expect(controller.busy, isFalse);
      expect(await controller.refresh(), isTrue);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );
}
