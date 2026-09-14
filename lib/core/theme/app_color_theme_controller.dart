import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_logger.dart';
import 'app_color_theme.dart';

/// Which [AppColorTheme] is active — settings' customisation page picks
/// it, `main.dart` reads it to build the app's actual [ThemeData]
/// ([AppTheme.lightWith]/[AppTheme.darkWith]).
///
/// On the device, like `ThemeController`/`AppIconController` — a display
/// preference for this install, nothing a reader would expect to follow
/// them to another device.
class AppColorThemeController {
  AppColorThemeController._();

  static const _key = 'app_theme.color';

  /// Defaults to [AppColorTheme.forest] every launch until [initialize]
  /// has read the saved choice back.
  static final ValueNotifier<AppColorTheme> current = ValueNotifier(
    AppColorTheme.forest,
  );

  /// Reads the saved choice. Called once from `_bootstrap`; failing here
  /// just leaves the app on forest a beat longer, never a startup
  /// failure.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == null) return;
      for (final theme in AppColorTheme.values) {
        if (theme.name == saved) {
          current.value = theme;
          return;
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'AppColorThemeController',
        'Could not read the saved color theme; leaving it forest.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(AppColorTheme theme) async {
    current.value = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, theme.name);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'AppColorThemeController',
        'Could not save the color theme.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
