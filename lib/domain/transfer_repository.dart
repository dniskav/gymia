import 'transfer.dart';

class BackupSummary {
  const BackupSummary(this.workouts, this.routines, this.active);
  final int workouts, routines;
  final bool active;
}

class ImportSummary {
  const ImportSummary(this.added, this.duplicates);
  final int added, duplicates;
}

abstract interface class TransferRepository {
  Future<String> createBackupJson();
  BackupSummary inspectBackupJson(String source);
  Future<void> restoreBackupJson(String source);
  Future<ImportSummary> importWorkouts(List<ImportedWorkout> workouts);
  Future<Set<String>> existingFingerprints();
}
