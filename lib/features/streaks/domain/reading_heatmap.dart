/// A year of reading days as intensity levels — what the stats page's
/// heatmap draws. Pure: built from per-day command counts, no Flutter, no
/// clock of its own (pass [today]), so it can be tested exactly.
///
/// A "reading day" is a local calendar day with at least one journaled
/// command on it — the same rule as `StreaksController.loggedDays` and the
/// add tab's streak, so the heatmap, the streak and the journal can never
/// disagree about whether a day counted. `delete` never counts; the caller
/// is expected to have filtered it out (see
/// `StreaksController.activityByDay`).
class ReadingHeatmap {
  ReadingHeatmap._(this._counts, {required this.year, required this.today});

  /// Builds the heatmap for [year] from [countsByDay] (any time of day on
  /// each key is ignored; days outside [year] and non-positive counts are
  /// dropped).
  factory ReadingHeatmap.fromCounts(
    int year,
    Map<DateTime, int> countsByDay, {
    required DateTime today,
  }) {
    final counts = <DateTime, int>{};
    for (final MapEntry(key: day, value: count) in countsByDay.entries) {
      if (day.year != year || count <= 0) continue;
      final key = dayKey(day);
      counts[key] = (counts[key] ?? 0) + count;
    }
    return ReadingHeatmap._(
      Map.unmodifiable(counts),
      year: year,
      today: dayKey(today),
    );
  }

  final int year;

  /// Midnight today, local — days after it haven't happened yet.
  final DateTime today;

  final Map<DateTime, int> _counts;

  /// The highest intensity [levelFor] returns.
  static const maxLevel = 4;

  static DateTime dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Commands journaled on [day].
  int countFor(DateTime day) => _counts[dayKey(day)] ?? 0;

  /// 0 for nothing logged, then 1..[maxLevel] by how much was: one
  /// command, two, three or four, five or more. Fixed thresholds rather
  /// than scaled to the reader's busiest day, so a square means the same
  /// thing in March as it does in November, and one huge import day can't
  /// wash every other day out to the palest shade.
  int levelFor(DateTime day) {
    final count = countFor(day);
    if (count <= 0) return 0;
    if (count == 1) return 1;
    if (count == 2) return 2;
    if (count <= 4) return 3;
    return maxLevel;
  }

  /// Whether [day] is still to come this year — drawn as an empty slot
  /// rather than a "nothing logged" square, so the grid doesn't read as a
  /// run of missed days ahead of the reader.
  bool isFuture(DateTime day) => dayKey(day).isAfter(today);

  /// How many distinct days in [year] had something logged.
  int get readingDays => _counts.length;

  /// Reading days in [month] (1-12).
  int readingDaysIn(int month) =>
      _counts.keys.where((day) => day.month == month).length;

  /// The month (1-12) with the most reading days, earliest on a tie; null
  /// when nothing was logged all year.
  int? get busiestMonth {
    int? best;
    var bestDays = 0;
    for (var month = 1; month <= 12; month++) {
      final days = readingDaysIn(month);
      if (days > bestDays) {
        best = month;
        bestDays = days;
      }
    }
    return best;
  }

  /// Days in [month] of [year] (1-12).
  int daysInMonth(int month) => DateTime(year, month + 1, 0).day;

  /// Blank cells before the 1st of [month] in a Monday-first week row.
  int leadingBlanks(int month) => DateTime(year, month).weekday - 1;
}
