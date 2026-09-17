import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../domain/daily_goal.dart';

/// The reader's [DailyGoal], on the device like `StartPageController` — a
/// habit kept on this phone. (The yearly books goal is the synced one; see
/// `GoalController`.)
class DailyGoalController {
  DailyGoalController._();

  static const _minutesKey = 'goals.daily_minutes';
  static const _doneKey = 'goals.daily_done_days';

  static final ValueNotifier<DailyGoal> goal = ValueNotifier(
    const DailyGoal(minutes: DailyGoal.defaultMinutes),
  );

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final minutes = prefs.getInt(_minutesKey);
      goal.value = DailyGoal(
        minutes: minutes != null && DailyGoal.minuteOptions.contains(minutes)
            ? minutes
            : DailyGoal.defaultMinutes,
        doneDays: {...?prefs.getStringList(_doneKey)},
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'DailyGoalController',
        'Could not read the daily goal.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> setMinutes(int minutes) =>
      _save(goal.value.withMinutes(minutes));

  static Future<void> toggle(DateTime day) => _save(goal.value.toggle(day));

  static Future<void> _save(DailyGoal next) async {
    goal.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_minutesKey, next.minutes);
      await prefs.setStringList(_doneKey, next.doneDays.toList()..sort());
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'DailyGoalController',
        'Could not save the daily goal.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @visibleForTesting
  static void reset([
    DailyGoal value = const DailyGoal(minutes: DailyGoal.defaultMinutes),
  ]) => goal.value = value;
}
