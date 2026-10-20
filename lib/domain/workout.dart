class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

String validName(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.length > 80) {
    throw const ValidationException(
      'Escribe un nombre de entre 1 y 80 caracteres.',
    );
  }
  return value;
}

// Store hundredths of a kg as an integer, avoiding floating-point drift.
int parseWeight(String raw) {
  final value = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(value)) {
    throw const ValidationException(
      'Usa un peso de 0 a 9999,99 kg, con hasta 2 decimales.',
    );
  }
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

int parseReps(String raw) {
  final value = raw.trim();
  final reps = int.tryParse(value);
  if (!RegExp(r'^\d{1,3}$').hasMatch(value) || reps == null || reps < 1) {
    throw const ValidationException('Introduce entre 1 y 999 repeticiones.');
  }
  return reps;
}

String formatWeight(int hundredths) {
  final whole = hundredths ~/ 100;
  final decimal = hundredths % 100;
  return decimal == 0
      ? '$whole'
      : '$whole,${decimal.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.weight,
    required this.reps,
    this.recordedAt,
  });
  final String id;
  final int weight;
  final int reps;
  // Capture time is not necessarily the time the exercise was performed.
  final DateTime? recordedAt;
}

class Exercise {
  Exercise({
    required this.id,
    required this.name,
    required List<WorkoutSet> sets,
    this.targetSets,
    this.repsMin,
    this.repsMax,
    this.restSeconds = 90,
  }) : sets = List.unmodifiable(sets);
  final String id;
  final String name;
  final List<WorkoutSet> sets;
  final int? targetSets, repsMin, repsMax;
  final int restSeconds;
}

class Workout {
  Workout({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.finishedAt,
    required List<Exercise> exercises,
    this.finishedRecordedAt,
    this.finishTimeSource,
    List<String> finishTimeIssues = const [],
  }) : exercises = List.unmodifiable(exercises),
       finishTimeIssues = List.unmodifiable(finishTimeIssues);
  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final DateTime? finishedRecordedAt;
  final FinishTimeSource? finishTimeSource;
  final List<String> finishTimeIssues;
  final List<Exercise> exercises;
  bool get isActive => finishedAt == null;
  int get setCount => exercises.fold(0, (n, e) => n + e.sets.length);
  int get repCount =>
      exercises.fold(0, (n, e) => n + e.sets.fold(0, (s, r) => s + r.reps));
}

enum FinishTimeSource { system, user }

class FinishTimeIssue {
  const FinishTimeIssue(this.code, this.message);
  final String code, message;
}

/// Inconsistent times are user-overridable observations, not an instruction
/// to silently repair or delete records. Unknown capture times remain unknown.
List<FinishTimeIssue> reviewFinishTime(
  Workout workout,
  Iterable<Workout> all,
  DateTime end,
  DateTime now, {
  Iterable<DateTime> activityEnds = const [],
}) {
  String stamp(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  final issues = <FinishTimeIssue>[];
  if (end.isBefore(workout.startedAt)) {
    issues.add(
      FinishTimeIssue(
        'before_start',
        'La hora elegida es anterior al inicio (${stamp(workout.startedAt)}).',
      ),
    );
  }
  final times =
      workout.exercises
          .expand((e) => e.sets)
          .map((s) => s.recordedAt)
          .whereType<DateTime>()
          .toList()
        ..sort();
  if (times.isNotEmpty && end.isBefore(times.last)) {
    issues.add(
      FinishTimeIssue(
        'before_last_record',
        'Hay una serie registrada a las ${stamp(times.last)}, después de la hora de finalización elegida. La hora de registro puede diferir de la de ejecución.',
      ),
    );
  }
  if (end.isAfter(now)) {
    issues.add(
      const FinishTimeIssue('in_future', 'La hora elegida está en el futuro.'),
    );
  }
  if (activityEnds.any((t) => end.isBefore(t))) {
    issues.add(
      const FinishTimeIssue(
        'before_last_activity',
        'La hora elegida es anterior al fin registrado de una actividad.',
      ),
    );
  }
  if (!end.isBefore(workout.startedAt)) {
    for (final other in all) {
      final otherEnd = other.finishedAt;
      if (other.id == workout.id ||
          otherEnd == null ||
          otherEnd.isBefore(other.startedAt)) {
        continue;
      }
      if (workout.startedAt.isBefore(otherEnd) &&
          other.startedAt.isBefore(end)) {
        issues.add(
          FinishTimeIssue(
            'overlap:${other.id}',
            'El horario se solapa con «${other.name}» (${stamp(other.startedAt)} – ${stamp(otherEnd)}).',
          ),
        );
      }
    }
  }
  return issues;
}
