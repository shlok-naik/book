import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';

/// Whether a series is shown as a patchwork of its covers or the single
/// fanned stack — settings' **reading → series tiles** row flips this;
/// the library page's series row and its shelf-grid grouped tile both
/// read it.
///
/// On the device, like [ThemeController]/`AppIconController` — a display
/// preference for this install, nothing a reader would expect to follow
/// them to another device.
class SeriesTileStyleController {
  SeriesTileStyleController._();

  static const _key = 'series_tiles.patchwork';

  /// Defaults to the fanned-stack look every launch until [initialize]
  /// has read the saved choice back.
  static final ValueNotifier<bool> patchwork = ValueNotifier(false);

  /// Reads the saved choice. Called once from `_bootstrap`; failing here
  /// just leaves the row showing the fanned look a beat longer, never a
  /// startup failure.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      patchwork.value = prefs.getBool(_key) ?? false;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SeriesTileStyleController',
        'Could not read the saved series tile style; leaving it fanned.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(bool value) async {
    patchwork.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SeriesTileStyleController',
        'Could not save the series tile style.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
