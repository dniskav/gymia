class RestTimerState {
  const RestTimerState({
    required this.workoutId,
    required this.durationSeconds,
    required this.remainingMs,
    this.endsAt,
  });
  final String workoutId;
  final int durationSeconds, remainingMs;
  final DateTime? endsAt;

  int remainingAt(DateTime now) =>
      (endsAt == null ? remainingMs : endsAt!.difference(now).inMilliseconds)
          .clamp(0, durationSeconds * 1000);
  bool runningAt(DateTime now) => endsAt != null && remainingAt(now) > 0;
  String displayAt(DateTime now) {
    final seconds = (remainingAt(now) / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
