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
    expect(find.textContaining('in a row'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('daily-goal-done')));
    await tester.pump();

    expect(DailyGoalController.goal.value.isDone(today), isTrue);
    expect(find.text('you read 10 minutes today'), findsOneWidget);
    expect(find.text('1 day in a row'), findsOneWidget);
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

  testWidgets('a streak reads back from the days already marked', (
    tester,
  ) async {
    DailyGoalController.reset(
      DailyGoal(
        minutes: 15,
        doneDays: {
          DailyGoal.keyOf(DateTime(2026, 9, 16)),
          DailyGoal.keyOf(DateTime(2026, 9, 15)),
        },
      ),
    );
    await pumpPrompt(tester);

    // Today is still open, so yesterday's run still counts.
    expect(find.text('have you read 15 minutes today?'), findsOneWidget);
    expect(find.text('2 days in a row'), findsOneWidget);
  });
}
