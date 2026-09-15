import 'package:book/features/streaks/domain/reading_heatmap.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stats page's reading-days heatmap. What matters is that a square
/// means the same thing everywhere (fixed thresholds), that days still to
/// come never read as missed ones, and that the month grid lines up with
/// the real calendar.
void main() {
  final today = DateTime(2026, 9, 14, 18, 30);

  ReadingHeatmap heatmap(Map<DateTime, int> counts) =>
      ReadingHeatmap.fromCounts(2026, counts, today: today);

  test('shades by fixed thresholds, not relative to the busiest day', () {
    final map = heatmap({
      DateTime(2026, 1, 1): 1,
      DateTime(2026, 1, 2): 2,
      DateTime(2026, 1, 3): 3,
      DateTime(2026, 1, 4): 4,
      DateTime(2026, 1, 5): 5,
      DateTime(2026, 1, 6): 40,
    });

    expect(map.levelFor(DateTime(2026, 1, 1)), 1);
    expect(map.levelFor(DateTime(2026, 1, 2)), 2);
    expect(map.levelFor(DateTime(2026, 1, 3)), 3);
    expect(map.levelFor(DateTime(2026, 1, 4)), 3);
    expect(map.levelFor(DateTime(2026, 1, 5)), ReadingHeatmap.maxLevel);
    // One huge day doesn't wash the one-command days out.
    expect(map.levelFor(DateTime(2026, 1, 6)), ReadingHeatmap.maxLevel);
    expect(map.levelFor(DateTime(2026, 1, 7)), 0);
  });

  test('ignores the time of day, other years and non-positive counts', () {
    final map = heatmap({
      DateTime(2026, 3, 1, 9): 1,
      DateTime(2026, 3, 1, 22): 1,
      DateTime(2025, 3, 1): 7,
      DateTime(2026, 3, 2): 0,
      DateTime(2026, 3, 3): -1,
    });

    expect(map.countFor(DateTime(2026, 3, 1)), 2);
    expect(map.readingDays, 1);
  });

  test('days after today are future, today is not', () {
    final map = heatmap(const {});
    expect(map.isFuture(DateTime(2026, 9, 14)), isFalse);
    expect(map.isFuture(DateTime(2026, 9, 15)), isTrue);
    expect(map.isFuture(DateTime(2026, 1, 1)), isFalse);
  });

  test('busiest month counts distinct days, earliest wins a tie', () {
    expect(heatmap(const {}).busiestMonth, isNull);

    final map = heatmap({
      DateTime(2026, 2, 1): 9, // one busy day
      DateTime(2026, 4, 1): 1,
      DateTime(2026, 4, 2): 1, // two quiet days beat it
      DateTime(2026, 6, 1): 1,
      DateTime(2026, 6, 2): 1,
    });
    expect(map.readingDaysIn(4), 2);
    expect(map.busiestMonth, 4);
  });

  test('month geometry matches the real calendar, Monday first', () {
    final map = heatmap(const {});
    // 1 Sep 2026 is a Tuesday: one blank before it.
    expect(map.leadingBlanks(9), 1);
    // 1 Feb 2026 is a Sunday: six blanks.
    expect(map.leadingBlanks(2), 6);
    expect(map.daysInMonth(2), 28);
    expect(map.daysInMonth(9), 30);
    expect(
      ReadingHeatmap.fromCounts(2028, const {}, today: today).daysInMonth(2),
      29,
    );
  });
}
