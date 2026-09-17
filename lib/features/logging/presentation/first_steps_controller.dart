import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../library/domain/library_book.dart';

/// One thing a new reader does once, in the order the add tab lists them.
enum FirstStep {
  addBook('add your first book'),
  logPage('log the page you\'re on'),
  setGoal('set a yearly goal'),
  finishBook('finish a book');

  const FirstStep(this.label);

  final String label;
}

/// Which [FirstStep]s are done — worked out from the shelf and the goal
/// themselves, never ticked by hand, so the list can't disagree with what
/// the reader actually did.
abstract final class FirstSteps {
  static Set<FirstStep> done({
    required List<LibraryBook> books,
    required int? goal,
  }) => {
    if (books.isNotEmpty) FirstStep.addBook,
    if (books.any((b) => b.currentPage > 0 || b.isFinished)) FirstStep.logPage,
    if (goal != null) FirstStep.setGoal,
    if (books.any((b) => b.isFinished)) FirstStep.finishBook,
  };
}

/// Whether the add tab shows its "first steps" checklist — the in-app
/// counterpart to onboarding's tour, for readers who learn by doing. Gone
/// for good once dismissed or once every step has been done; on the device,
/// like `StartPageController`.
///
/// Hidden until [initialize] has run — widget tests never run `_bootstrap`,
/// so the add tab looks as it always has there unless a test turns it on.
class FirstStepsController {
  FirstStepsController._();

  static const _key = 'logging.first_steps_finished';

  static final ValueNotifier<bool> visible = ValueNotifier(false);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      visible.value = !(prefs.getBool(_key) ?? false);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'FirstStepsController',
        'Could not read whether first steps were finished.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Hides the checklist for good — the reader closed it, or did it all.
  static Future<void> finish() async {
    if (!visible.value) return;
    visible.value = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'FirstStepsController',
        'Could not save that first steps were finished.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @visibleForTesting
  static void reset({bool visible = false}) =>
      FirstStepsController.visible.value = visible;
}
