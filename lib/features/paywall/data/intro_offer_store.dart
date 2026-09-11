import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';

/// Remembers whether the reader has already been shown the one-time
/// intro paywall popup.
///
/// On the device rather than in Supabase on purpose: it has to be
/// readable in the first frame after launch, before any network call,
/// and it describes this install rather than this reader — an anonymous
/// account is per-install anyway, so there is nothing for a server-side
/// flag to survive.
///
/// Both calls swallow storage failures and treat the offer as **already
/// seen**. A reader whose preferences can't be read is a rare edge; a
/// reader who gets the same popup on every single launch because the
/// write silently failed is a much worse one. The failure is logged
/// either way.
class IntroOfferStore {
  const IntroOfferStore();

  static const _key = 'paywall.intro_offer_seen';

  /// Whether the popup has already had its one chance.
  Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'IntroOfferStore',
        'Could not read the intro-offer flag; treating it as seen.',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  /// Records that it has. Called as the popup is presented, not when it
  /// is dismissed — a reader who kills the app mid-paywall has still
  /// seen it, and should not be met with it again on relaunch.
  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'IntroOfferStore',
        'Could not record that the intro offer was shown.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
