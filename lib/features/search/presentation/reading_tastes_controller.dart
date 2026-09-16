import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../domain/reading_taste.dart';

/// The kinds of books the reader likes ([ReadingTaste]) — picked in
/// onboarding's "what do you like to read?" and settings' profile section,
/// read by the search tab's recommendations. On the device, like
/// `StartPageController`.
class ReadingTastesController {
  ReadingTastesController._();

  static const _key = 'profile.reading_tastes';

  /// In [ReadingTaste] order, whatever order they were picked in.
  static final ValueNotifier<List<ReadingTaste>> tastes = ValueNotifier(
    const [],
  );

  /// Reads the saved choice. Called once from `_bootstrap`.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key) ?? const [];
      tastes.value = _ordered({
        for (final taste in ReadingTaste.values)
          if (saved.contains(taste.name)) taste,
      });
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ReadingTastesController',
        'Could not read the saved reading tastes.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(Set<ReadingTaste> next) async {
    tastes.value = _ordered(next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [
        for (final taste in tastes.value) taste.name,
      ]);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ReadingTastesController',
        'Could not save the reading tastes.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static List<ReadingTaste> _ordered(Set<ReadingTaste> set) =>
      List.unmodifiable([
        for (final taste in ReadingTaste.values)
          if (set.contains(taste)) taste,
      ]);

  @visibleForTesting
  static void reset() => tastes.value = const [];
}
