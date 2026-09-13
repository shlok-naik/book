import 'package:flutter/widgets.dart';

import 'controllers/goal_controller.dart';

/// Injects the app's one [GoalController], the same way `LibraryScope` and
/// `MemoryScope` inject theirs.
class GoalScope extends InheritedNotifier<GoalController> {
  const GoalScope({
    super.key,
    required GoalController controller,
    required super.child,
  }) : super(notifier: controller);

  static GoalController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GoalScope>();
    assert(scope != null, 'No GoalScope found above this widget.');
    return scope!.notifier!;
  }

  static GoalController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<GoalScope>();
    assert(scope != null, 'No GoalScope found above this widget.');
    return scope!.notifier!;
  }
}
