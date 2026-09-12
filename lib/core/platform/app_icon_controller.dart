import 'package:flutter/foundation.dart';

import '../diagnostics/app_logger.dart';
import 'app_icon.dart';
import 'app_icon_channel.dart';

/// Which launcher icon is active, mirrored from the OS rather than kept
/// as our own copy — iOS remembers the alternate icon name and Android
/// remembers which activity-alias is enabled, so re-reading that on
/// every launch is what keeps this notifier from drifting out of sync
/// with what the home screen actually shows. Unlike [ThemeController]
/// there is nothing to default to on a fresh install other than what
/// [initialize] reads back: the primary launcher icon is always
/// [AppIcon.originalLight].
class AppIconController {
  AppIconController._();

  static final ValueNotifier<AppIcon> current = ValueNotifier(
    AppIcon.originalLight,
  );

  static AppIconChannel _channel = const AppIconChannel();

  /// Test seam: swap in a fake before [initialize] or [select] run.
  @visibleForTesting
  static set channel(AppIconChannel value) => _channel = value;

  /// Reads the icon the OS is actually showing. Called once from
  /// `_bootstrap`; failing here just leaves the settings row showing
  /// "light" a beat longer, never a startup failure.
  static Future<void> initialize() async {
    try {
      current.value = await _channel.current();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'AppIconController',
        'Could not read the current app icon; leaving it as original/light.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Switches the launcher icon. Rethrows so the settings row can tell
  /// a reader who dismissed iOS's own confirmation dialog apart from one
  /// whose tap actually worked, rather than reporting success either way.
  static Future<void> select(AppIcon next) async {
    if (current.value == next) return;
    await _channel.set(next);
    current.value = next;
  }
}
