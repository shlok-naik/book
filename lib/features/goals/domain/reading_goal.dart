/// A failure from [GoalRepository], already worded for the reader.
class GoalException implements Exception {
  const GoalException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GoalException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Progress towards a yearly reading goal: [finished] books out of [goal]
/// in [year].
class ReadingGoal {
  const ReadingGoal({
    required this.goal,
    required this.finished,
    required this.year,
  });

  static const min = 1;
  static const max = 1000;

  /// What the picker starts on when the reader has never set a goal.
  static const suggested = 12;

  static bool isValid(int goal) => goal >= min && goal <= max;

  final int goal;
  final int finished;
  final int year;

  /// 0..1 — capped, so a reader past their goal still sees a full bar.
  double get fraction => (finished / goal).clamp(0.0, 1.0);

  bool get isComplete => finished >= goal;

  int get remaining => isComplete ? 0 : goal - finished;

  /// How many books a steady pace would have finished by [now] — used to
  /// say "on track" or "N behind" without judging the first days of
  /// January too harshly (it rounds down).
  int expectedBy(DateTime now) {
    if (now.year != year) return now.year > year ? goal : 0;
    final start = DateTime(year);
    final end = DateTime(year + 1);
    final elapsed =
        now.difference(start).inHours / end.difference(start).inHours;
    return (goal * elapsed).floor();
  }

  /// "3 ahead", "on track", "2 behind" or "goal reached".
  String paceLabel(DateTime now) {
    if (isComplete) return 'goal reached';
    final difference = finished - expectedBy(now);
    if (difference == 0) return 'on track';
    return difference > 0 ? '$difference ahead' : '${-difference} behind';
  }

  /// "7 of 24 books in 2026".
  String get summary =>
      '$finished of $goal ${goal == 1 ? 'book' : 'books'} in $year';
}
