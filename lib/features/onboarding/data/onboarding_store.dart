import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';

/// Remembers whether the reader has already been through the intro.
///
/// On the device rather than in Supabase, for the same reasons as
/// `IntroOfferStore`: it has to be readable in the first frame after
/// launch, before any network call, and it describes this install rather
/// than this reader.
///
/// It could not live on the session even if we wanted it to. Onboarding
/// no longer creates an account — `main` opens an anonymous one before
/// the first frame either way — so "is this reader signed in" is true on
/// the very first launch and can no longer stand in for "has this reader
/// seen the intro".
///
/// Both calls swallow storage failures and treat the intro as **already
/// seen**. A reader whose preferences can't be read is a rare edge; a
/// reader made to sit through the welcome animation on every single
/// launch because the write silently failed is a much worse one. The
/// failure is logged either way.
class OnboardingStore {
  const OnboardingStore();

  static const _key = 'onboarding.completed';

  /// Whether the intro has already run. False only on a fresh install.
  Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OnboardingStore',
        'Could not read the onboarding flag; treating it as seen.',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    }
  }

  /// Records that it has. Called from the last screen, as the reader
  /// steps into the app — not from the first, because a reader who quits
  /// halfway through the intro has not had it.
  Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OnboardingStore',
        'Could not record that onboarding finished.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
