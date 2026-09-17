/// A daily reading habit, Apple Books-style: how many minutes a day the
/// reader means to read, and which days they marked it done. Pure — dates
/// in, answers out.
class DailyGoal {
  const DailyGoal({required this.minutes, this.doneDays = const {}});

  /// The choices the "adjust goal" sheet offers.
  static const minuteOptions = [5, 10, 15, 20, 30, 45, 60];
  static const defaultMinutes = 10;

  /// Days kept — a year's streak and then some.
  static const keepDays = 400;

  final int minutes;

  /// Local calendar days marked done, as `YYYY-MM-DD`.
  final Set<String> doneDays;

  static String keyOf(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  bool isDone(DateTime day) => doneDays.contains(keyOf(day));

  /// Marks [day] done, or not done again. Forgets days older than
  /// [keepDays].
  DailyGoal toggle(DateTime day) {
    final key = keyOf(day);
    final next = {...doneDays};
    if (!next.remove(key)) next.add(key);
    final oldest = keyOf(DateTime(day.year, day.month, day.day - keepDays));
    next.removeWhere((k) => k.compareTo(oldest) < 0);
    return DailyGoal(minutes: minutes, doneDays: next);
  }

  DailyGoal withMinutes(int value) =>
      DailyGoal(minutes: value, doneDays: doneDays);

  /// Days in a row the goal was met, ending today — or yesterday while today
  /// is still open: a streak isn't broken until the day is over.
  int streak(DateTime today) {
    var day = DateTime(today.year, today.month, today.day);
    if (!isDone(day)) day = DateTime(day.year, day.month, day.day - 1);
    var count = 0;
    while (isDone(day)) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }

  /// The longest run of done days on record.
  int get best {
    final days = [for (final key in doneDays) ?DateTime.tryParse(key)]..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      final follows =
          previous != null &&
          DateTime(previous.year, previous.month, previous.day + 1) == day;
      run = follows ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }

  /// Monday to Sunday of the week holding [today].
  static List<DateTime> weekOf(DateTime today) {
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.monday),
    );
    return [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
  }
}
