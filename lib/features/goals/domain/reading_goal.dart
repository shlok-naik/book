/// A failure from [GoalRepository], already worded for the reader.
class GoalException implements Exception {
  const GoalException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GoalException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Where pace starts counting from after a library import: the moment of
/// the import ([at]) and how many books the import brought in as already
/// finished that year ([books]). See `ReadingStats.paceBaseline`.
class PaceBaseline {
  const PaceBaseline({required this.at, required this.books});

  final DateTime at;
  final int books;
}

/// Progress towards a yearly reading goal: [finished] books out of [goal]
/// in [year].
class ReadingGoal {
  const ReadingGoal({
    required this.goal,
    required this.finished,
    required this.year,
    this.baseline,
  });

  /// Set when the reader imported their library during [year]: a steady
  /// pace is measured from the import onwards, starting at the books the
  /// import already had finished — not from January 1st at zero, which
  /// would call a reader who imported in September hopelessly behind (or,
  /// with a big import, far ahead) for reading they never did in cactus.
  final PaceBaseline? baseline;

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
  ///
  /// With a [baseline], nothing is expected beyond it until the import: from
  /// then the pace runs from its book count up to [goal] over what was left
  /// of the year.
  int expectedBy(DateTime now) {
    if (now.year != year) return now.year > year ? goal : 0;
    final end = DateTime(year + 1);
    final base = baseline;
    if (base != null && base.at.toLocal().year == year) {
      final from = base.at.toLocal();
      if (!now.isAfter(from)) return base.books;
      final span = end.difference(from).inMinutes;
      if (span <= 0) return goal;
      final elapsed = now.difference(from).inMinutes / span;
      final remaining = goal - base.books;
      if (remaining <= 0) return base.books;
      return base.books + (remaining * elapsed).floor();
    }
    final start = DateTime(year);
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
