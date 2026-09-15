import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_logger.dart';
import 'app_font_theme.dart';

/// Which [AppFontTheme] is active — settings' customisation page picks it,
/// `main.dart` reads it to build the app's [ThemeData]
/// ([AppTheme.lightWith]/[AppTheme.darkWith]).
///
/// On the device, like [AppColorThemeController] — a display preference
/// for this install.
class AppFontThemeController {
  AppFontThemeController._();

  static const _key = 'app_theme.font';

  /// [AppFontTheme.original] until [initialize] reads the saved choice.
  static final ValueNotifier<AppFontTheme> current = ValueNotifier(
    AppFontTheme.original,
  );

  /// Reads the saved choice. Called once from `_bootstrap`; a failure just
  /// leaves the app on the original fonts, never a startup failure.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == null) return;
      for (final theme in AppFontTheme.values) {
        if (theme.name == saved) {
          current.value = theme;
          return;
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'AppFontThemeController',
        'Could not read the saved font theme; leaving it original.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(AppFontTheme theme) async {
    current.value = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, theme.name);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'AppFontThemeController',
        'Could not save the font theme.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
