import 'dart:async';

import 'package:book/features/goals/data/goal_repository.dart';
import 'package:book/features/goals/domain/reading_goal.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';

/// An in-memory reading goal, so nothing under test reaches Supabase.
class FakeGoalRepository extends GoalRepository {
  FakeGoalRepository({this.goal, this.failure});

  int? goal;

  /// Thrown by both reads and writes when set.
  GoalException? failure;

  final saved = <int?>[];

  @override
  Future<int?> fetchGoal() async {
    if (failure != null) throw failure!;
    return goal;
  }

  @override
  Future<void> saveGoal(int? goal) async {
    if (failure != null) throw failure!;
    saved.add(goal);
    this.goal = goal;
  }
}

/// A [GoalController] over a [FakeGoalRepository], already loaded unless
/// [load] is false.
Future<GoalController> fakeGoalController({
  int? goal,
  bool load = true,
  GoalException? failure,
}) async {
  final controller = GoalController(
    repository: FakeGoalRepository(goal: goal, failure: failure),
  );
  if (load) await controller.load();
  return controller;
}

/// Synchronous variant for harness builders that can't await: loads in the
/// background, which a following `pump` flushes.
GoalController goalControllerFor({int? goal}) {
  final controller = GoalController(repository: FakeGoalRepository(goal: goal));
  unawaited(controller.load());
  return controller;
}
