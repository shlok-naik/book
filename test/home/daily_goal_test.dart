import 'package:book/features/goals/domain/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Thursday.
  final today = DateTime(2026, 9, 17);

  DailyGoal doneOn(List<DateTime> days) {
    var goal = const DailyGoal(minutes: 10);
    for (final day in days) {
      goal = goal.toggle(day);
    }
    return goal;
  }

  test('toggling marks and unmarks a day', () {
    final goal = doneOn([today]);
    expect(goal.isDone(today), isTrue);
    expect(goal.toggle(today).isDone(today), isFalse);
  });

  test('a streak runs back from today', () {
    final goal = doneOn([today, DateTime(2026, 9, 16), DateTime(2026, 9, 15)]);
    expect(goal.streak(today), 3);
  });

  test('an open today keeps yesterday going', () {
    final goal = doneOn([DateTime(2026, 9, 16), DateTime(2026, 9, 15)]);
    expect(goal.streak(today), 2);
  });

  test('a missed day ends it', () {
    final goal = doneOn([today, DateTime(2026, 9, 15)]);
    expect(goal.streak(today), 1);
  });

  test('best is the longest run, across months', () {
    final goal = doneOn([
      DateTime(2026, 8, 30),
      DateTime(2026, 8, 31),
      DateTime(2026, 9, 1),
      today,
    ]);
    expect(goal.best, 3);
  });

  test('the week runs Monday to Sunday', () {
    final week = DailyGoal.weekOf(today);
    expect(week.first, DateTime(2026, 9, 14));
    expect(week.last, DateTime(2026, 9, 20));
  });
}
