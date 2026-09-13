/// Day-streak arithmetic over a set of local calendar days on which
/// something was logged (a `delete` never counts — callers filter it out
/// before building the set). Shared by the add tab's streak readout and
/// the stats page so the two can never disagree.
abstract final class StreakMath {
  static DateTime dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Consecutive days ending today — or yesterday, so a streak isn't
  /// "broken" first thing in the morning before today's reading.
  static int current(Set<DateTime> loggedDays, {DateTime? now}) {
    if (loggedDays.isEmpty) return 0;
    final today = dayKey(now ?? DateTime.now());
    var cursor = loggedDays.contains(today) ? today : _previous(today);
    var streak = 0;
    while (loggedDays.contains(cursor)) {
      streak++;
      cursor = _previous(cursor);
    }
    return streak;
  }

  /// The longest run of consecutive days anywhere in [loggedDays].
  static int longest(Set<DateTime> loggedDays) {
    var best = 0;
    for (final day in loggedDays) {
      if (loggedDays.contains(_previous(day))) continue;
      var length = 1;
      var cursor = _next(day);
      while (loggedDays.contains(cursor)) {
        length++;
        cursor = _next(cursor);
      }
      if (length > best) best = length;
    }
    return best;
  }

  // Calendar arithmetic rather than `Duration(days: 1)`, which is 24 hours
  // and lands on the wrong day across a daylight-saving change.
  static DateTime _previous(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);

  static DateTime _next(DateTime day) =>
      DateTime(day.year, day.month, day.day + 1);
}
