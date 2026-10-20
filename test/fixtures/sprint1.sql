-- Frozen v1 schema from Sprint 1. Do not update when the current schema changes.
CREATE TABLE workouts (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  started_at INTEGER NOT NULL, finished_at INTEGER,
  active_slot INTEGER UNIQUE DEFAULT 1,
  CHECK ((finished_at IS NULL AND active_slot IS 1)
    OR (finished_at IS NOT NULL AND active_slot IS NULL)));
CREATE TABLE exercises (
  id TEXT PRIMARY KEY, workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  name TEXT NOT NULL, position INTEGER NOT NULL);
CREATE INDEX exercises_workout ON exercises(workout_id);
CREATE TABLE sets (
  id TEXT PRIMARY KEY, exercise_id TEXT NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  weight INTEGER NOT NULL CHECK(weight BETWEEN 0 AND 999999),
  reps INTEGER NOT NULL CHECK(reps BETWEEN 1 AND 999), position INTEGER NOT NULL);
CREATE INDEX sets_exercise ON sets(exercise_id);
