import 'workout.dart';

String exerciseKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int parseTargetSets(String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null || n < 1 || n > 30) {
    throw const ValidationException('Usa entre 1 y 30 series.');
  }
  return n;
}

int parseRestSeconds(String raw) {
  final n = int.tryParse(raw.trim());
  if (n == null || n < 5 || n > 1800) {
    throw const ValidationException('Usa entre 5 y 1800 segundos.');
  }
  return n;
}

class RoutineExerciseDraft {
  const RoutineExerciseDraft({
    required this.name,
    this.targetSets = 3,
    this.repsMin = 8,
    this.repsMax = 12,
    this.restSeconds = 90,
  });
  final String name;
  final int targetSets, repsMin, repsMax, restSeconds;

  void validate() {
    validName(name);
    parseTargetSets('$targetSets');
    parseReps('$repsMin');
    parseReps('$repsMax');
    parseRestSeconds('$restSeconds');
    if (repsMin > repsMax) {
      throw const ValidationException(
        'El mínimo de repeticiones no puede superar al máximo.',
      );
    }
  }

  String get description =>
      '$targetSets series · $repsMin–$repsMax reps · ${restSeconds}s descanso';
}

class Routine {
  Routine({
    required this.id,
    required this.name,
    required List<RoutineExerciseDraft> exercises,
  }) : exercises = List.unmodifiable(exercises);
  final String id, name;
  final List<RoutineExerciseDraft> exercises;
}

class PreviousPerformance {
  PreviousPerformance({required this.date, required List<WorkoutSet> sets})
    : sets = List.unmodifiable(sets);
  final DateTime date;
  final List<WorkoutSet> sets;
}
