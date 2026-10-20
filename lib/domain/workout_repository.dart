import 'workout.dart';
import 'routine.dart';
import 'rest_timer.dart';

abstract interface class WorkoutRepository {
  Future<List<Workout>> load();
  Future<List<Routine>> loadRoutines();
  Future<String> saveRoutine({
    String? id,
    required String name,
    required List<RoutineExerciseDraft> exercises,
  });
  Future<void> deleteRoutine(String id);
  Future<String> startRoutine(String id);
  Future<RestTimerState?> loadRestTimer();
  Future<void> startRest(String workoutId, int seconds);
  Future<void> pauseRest(String workoutId);
  Future<void> resumeRest(String workoutId);
  Future<void> resetRest(String workoutId, int seconds);
  Future<String> start(String name);
  Future<void> addExercise(String workoutId, String name);
  Future<void> addSet(String exerciseId, String weight, String reps);
  Future<void> editSet(String setId, String weight, String reps);
  Future<void> deleteSet(String setId);
  Future<void> deleteExercise(String exerciseId);
  Future<void> finish(
    String workoutId, {
    DateTime? finishedAt,
    FinishTimeSource finishTimeSource = FinishTimeSource.user,
    bool acceptTimeConflicts = false,
  });
  Future<void> discard(String workoutId);
  Future<void> close();
}
