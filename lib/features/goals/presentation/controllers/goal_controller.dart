import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../data/goal_repository.dart';
import '../../domain/reading_goal.dart';

/// The reader's yearly reading goal — the single mutation point for it,
/// whether it is set during onboarding, from settings, or from the stats
/// and add pages. Progress against it is not held here: that is a count of
/// the shelf's finished books, which only `LibraryController` knows, so
/// widgets combine the two (see `ReadingStats.goalProgress`).
class GoalController extends ChangeNotifier {
  GoalController({GoalRepository? repository})
    : repository = repository ?? GoalRepository();

  final GoalRepository repository;

  int? _goal;
  bool _loaded = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// The saved goal, or null when there isn't one (or it hasn't loaded).
  int? get goal => _goal;

  /// True once a load has succeeded — until then a null [goal] means
  /// "unknown", not "no goal", and nothing should offer to set one.
  bool get isLoaded => _loaded;

  bool get isLoading => _isLoading;

  /// Set when the last [load] failed.
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _goal = await repository.fetchGoal();
      _loaded = true;
    } on GoalException catch (error) {
      _errorMessage = error.message;
      AppLogger.error(
        'GoalController',
        'Loading the reading goal failed.',
        error: error,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves [goal] (null clears it). Optimistic with rollback, like every
  /// shelf command. Returns null on success, or a message to show.
  Future<String?> setGoal(int? goal) async {
    if (goal != null && !ReadingGoal.isValid(goal)) {
      return 'A goal has to be between ${ReadingGoal.min} and '
          '${ReadingGoal.max} books.';
    }
    if (_loaded && goal == _goal) return null;

    final previous = _goal;
    final wasLoaded = _loaded;
    _goal = goal;
    _loaded = true;
    notifyListeners();
    try {
      await repository.saveGoal(goal);
      return null;
    } on GoalException catch (error) {
      _goal = previous;
      _loaded = wasLoaded;
      notifyListeners();
      return error.message;
    }
  }
}
