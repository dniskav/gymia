import 'package:flutter/foundation.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';
import '../domain/routine.dart';
import '../domain/rest_timer.dart';
import '../domain/activity.dart';

class WorkoutController extends ChangeNotifier {
  WorkoutController(
    this.repository, {
    DateTime Function()? clock,
    this.profileId = 'local',
  }) : now = clock ?? DateTime.now;
  final WorkoutRepository repository;
  final String profileId;
  final DateTime Function() now;
  List<Workout> workouts = [];
  List<Routine> routines = [];
  RestTimerState? restTimer;
  List<FocusActivity> activities = [];
  ActivityRepository? get activityRepository =>
      repository is ActivityRepository
          ? repository as ActivityRepository
          : null;
  FocusActivity? get focus => activities.where((a) => a.active).firstOrNull;
  bool busy = false;
  bool loaded = false;
  String? error;
  Workout? get active => workouts.where((w) => w.isActive).firstOrNull;
  List<Workout> get history => workouts.where((w) => !w.isActive).toList();

  Future<bool> run(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    var ok = false;
    try {
      await action();
      workouts = await repository.load();
      routines = await repository.loadRoutines();
      restTimer = await repository.loadRestTimer();
      activities = await activityRepository?.loadActivities() ?? [];
      loaded = true;
      ok = true;
    } on ValidationException catch (e) {
      error = e.message;
    } catch (e, stack) {
      debugPrint('Storage error: $e\n$stack');
      error = 'No se pudo completar la operación. Inténtalo de nuevo.';
    } finally {
      busy = false;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> refresh() => run(() async {});

  PreviousPerformance? previousFor(Exercise exercise, Workout current) {
    final candidates =
        history
            .where(
              (w) =>
                  w.id != current.id &&
                  !w.finishedAt!.isAfter(current.startedAt),
            )
            .toList()
          ..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!));
    for (final w in candidates) {
      final sets =
          w.exercises
              .where((e) => exerciseKey(e.name) == exerciseKey(exercise.name))
              .expand((e) => e.sets)
              .toList();
      if (sets.isNotEmpty) {
        return PreviousPerformance(date: w.startedAt, sets: sets);
      }
    }
    return null;
  }
}
