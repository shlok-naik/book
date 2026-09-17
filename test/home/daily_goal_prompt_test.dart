import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/domain/daily_goal.dart';
import 'package:book/features/goals/presentation/daily_goal_controller.dart';
import 'package:book/features/goals/presentation/widgets/daily_goal_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The add tab's daily habit — the question that replaced the yearly goal
/// under the currently-reading card.
void main() {
  final today = DateTime(2026, 9, 17);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DailyGoalController.reset();
  });

  tearDown(DailyGoalController.reset);

  Future<void> pumpPrompt(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: DailyGoalPrompt(now: today)),
      ),
    );
    await tester.pump();
  }

  testWidgets('asks about today, and a tick answers it', (tester) async {
    await pumpPrompt(tester);

    expect(find.text('have you read 10 minutes today?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('daily-goal-done')));
    await tester.pump();

    expect(DailyGoalController.goal.value.isDone(today), isTrue);
    expect(find.text('you read 10 minutes today'), findsOneWidget);
    // The run itself is counted by the streak row underneath, not here.
    expect(find.textContaining('in a row'), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
  });

  testWidgets('tapping it again takes today back', (tester) async {
    DailyGoalController.reset(
      DailyGoal(minutes: 10, doneDays: {DailyGoal.keyOf(today)}),
    );
    await pumpPrompt(tester);

    await tester.tap(find.byKey(const ValueKey('daily-goal-done')));
    await tester.pump();

    expect(DailyGoalController.goal.value.isDone(today), isFalse);
  });

  testWidgets('the question itself changes how many minutes it asks for', (
    tester,
  ) async {
    await pumpPrompt(tester);

    await tester.tap(find.byKey(const ValueKey('daily-goal-question')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('daily-goal-minutes-30')));
    await tester.pump();

    expect(DailyGoalController.goal.value.minutes, 30);
    // The sheet is still open, showing the new choice.
    expect(find.text('minutes a day'), findsOneWidget);
  });

  testWidgets('asks in the number of minutes the reader picked', (
    tester,
  ) async {
    DailyGoalController.reset(
      DailyGoal(
        minutes: 15,
        doneDays: {DailyGoal.keyOf(DateTime(2026, 9, 16))},
      ),
    );
    await pumpPrompt(tester);

    expect(find.text('have you read 15 minutes today?'), findsOneWidget);
  });

  test('the days ticked are what the streak row reads', () {
    final goal = DailyGoal(
      minutes: 10,
      doneDays: {
        DailyGoal.keyOf(today),
        DailyGoal.keyOf(DateTime(2026, 9, 16)),
      },
    );
    expect(goal.markedDays, {today, DateTime(2026, 9, 16)});
  });
}
