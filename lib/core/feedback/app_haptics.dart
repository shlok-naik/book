import 'package:flutter/services.dart';

import '../diagnostics/app_logger.dart';

/// The app's haptic vocabulary, in one place.
///
/// Three rules keep it from becoming noise, which is the failure mode of
/// haptics in most apps:
///
/// * **One meaning per pattern.** [selection] is "you moved somewhere",
///   [accepted] is "the thing you asked for happened", [rejected] is "it
///   did not". Nothing else has a haptic.
/// * **Only on direct manipulation.** A haptic answers a touch the
///   reader just made. Nothing fires from a background event, a timer, or
///   a screen appearing on its own.
/// * **Never load-bearing.** Every call is fire-and-forget and swallows
///   its own platform failure — a device with no haptic engine, or one
///   whose user has switched haptics off, must not surface an error.
///
/// Kept as a class of static methods rather than an injected service:
/// like logging, this is ambient, and threading it through constructors
/// would buy nothing. [enabled] exists so widget tests can assert on
/// behaviour without the platform channel answering.
abstract final class AppHaptics {
  /// Set false in tests. In the app this stays true — the system's own
  /// haptics setting is what turns them off for a reader who does not
  /// want them, and second-guessing that in app code is how you end up
  /// ignoring an accessibility preference.
  static bool enabled = true;

  /// Moving between things: switching tabs, opening a day on the streak
  /// grid. The lightest pattern there is.
  static void selection() => _run(HapticFeedback.selectionClick);

  /// A command the reader typed was understood and applied.
  static void accepted() => _run(HapticFeedback.lightImpact);

  /// A command was not understood, or could not be applied. Heavier than
  /// [accepted] on purpose — this is the one the reader needs to notice
  /// without looking.
  static void rejected() => _run(HapticFeedback.heavyImpact);

  static void _run(Future<void> Function() pattern) {
    if (!enabled) return;
    reportingFailure(
      pattern(),
      source: 'AppHaptics',
      message: 'Haptic feedback was unavailable.',
    );
  }
}
