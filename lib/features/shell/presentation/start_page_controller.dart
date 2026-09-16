import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';

/// The tabs a reader can pick to open the app on — settings' **starting
/// page** rows. Stats isn't one: it's somewhere a reader goes to look,
/// not somewhere they start from.
enum StartPage {
  add('add'),
  search('search'),
  library('library');

  const StartPage(this.label);

  /// Lowercase, the same wording as the tab's own `TopBar` title.
  final String label;
}

/// Which tab `RootShell` opens on. On the device, like
/// `SeriesTileStyleController` — a preference for this install, nothing a
/// reader would expect to follow them to another device.
class StartPageController {
  StartPageController._();

  static const _key = 'shell.start_page';

  /// Defaults to [StartPage.add] — where the app has always opened — until
  /// [initialize] has read the saved choice back.
  static final ValueNotifier<StartPage> page = ValueNotifier(StartPage.add);

  /// Reads the saved choice. Called once from `_bootstrap`, before the first
  /// frame, so the shell opens on the right tab rather than switching.
  /// Failing here just opens on add.
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      page.value = StartPage.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => StartPage.add,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'StartPageController',
        'Could not read the saved starting page; opening on add.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(StartPage next) async {
    page.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next.name);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'StartPageController',
        'Could not save the starting page.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Back to the default, for tests.
  @visibleForTesting
  static void reset() => page.value = StartPage.add;
}
