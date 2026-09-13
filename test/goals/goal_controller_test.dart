import 'package:book/features/goals/domain/reading_goal.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_goals.dart';

void main() {
  test('loads the saved goal', () async {
    final controller = await fakeGoalController(goal: 24);
    expect(controller.isLoaded, isTrue);
    expect(controller.goal, 24);
  });

  test('a failed load is an error, not "no goal"', () async {
    final controller = await fakeGoalController(
      failure: const GoalException('offline'),
    );
    expect(controller.isLoaded, isFalse);
    expect(controller.errorMessage, 'offline');
  });

  test('setGoal saves and clears', () async {
    final repository = FakeGoalRepository();
    final controller = GoalController(repository: repository);
    await controller.load();

    expect(await controller.setGoal(30), isNull);
    expect(controller.goal, 30);
    expect(await controller.setGoal(null), isNull);
    expect(controller.goal, isNull);
    expect(repository.saved, [30, null]);
  });

  test('setGoal rolls back when the write fails', () async {
    final repository = FakeGoalRepository(goal: 10);
    final controller = GoalController(repository: repository);
    await controller.load();
    repository.failure = const GoalException('could not save');

    expect(await controller.setGoal(20), 'could not save');
    expect(controller.goal, 10);
  });

  test('setGoal refuses an out-of-range goal without writing', () async {
    final repository = FakeGoalRepository();
    final controller = GoalController(repository: repository);
    await controller.load();

    expect(await controller.setGoal(0), isNotNull);
    expect(repository.saved, isEmpty);
  });
}
