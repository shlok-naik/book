import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics/app_logger.dart';

/// Product analytics: which screens readers reach, and what happens at
/// the paywall.
///
/// The question this exists to answer is where people stop: the intro's
/// own screens, the four tabs, the settings screen, and the paywall
/// popup — which is the only place a conversion can happen now that
/// nothing is forced.
///
/// **What is never sent.** No book titles, no author names, no typed
/// commands, no profile answers, no email — none of it leaves the device
/// through here. Those are the reader's own words about their own
/// reading, and shipping them to a third party to satisfy curiosity about
/// a funnel is not a trade worth making. Every event below is either a
/// screen name that already exists in the source, or an enum-like
/// constant. If you find yourself adding a parameter whose value came
/// from a text field, stop.
///
/// Attaches the same way [CrashReporter] does — inert until [attach] has
/// run, because `FirebaseAnalytics.instance` throws synchronously when
/// Firebase was never initialized, and widget tests never run `main`.
abstract final class AppAnalytics {
  static FirebaseAnalytics? _analytics;

  static bool get isAttached => _analytics != null;

  /// Call once at startup, *after* Firebase has been initialized — which
  /// is [CrashReporter.attach]'s job, so this is only safe once that has
  /// returned true.
  static void attach() {
    try {
      _analytics = FirebaseAnalytics.instance;
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'AppAnalytics',
        'Analytics is unavailable; continuing without it.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Passed to `MaterialApp.navigatorObservers`, so a screen view is
  /// recorded from the route's own name rather than from a line in every
  /// page's `initState` that someone will eventually forget to add. Empty
  /// until [attach] has run.
  ///
  /// Only routes pushed with a [RouteSettings] name are reported — see
  /// the `settings:` argument on the settings route in `TopBar` and on
  /// the paywall popup in `showPaywallPopup`. An unnamed route is
  /// silently skipped, which is the right default: a screen nobody named
  /// is not a screen worth a funnel step.
  static List<NavigatorObserver> get navigatorObservers {
    final analytics = _analytics;
    if (analytics == null) return const [];
    return [FirebaseAnalyticsObserver(analytics: analytics)];
  }

  /// Ties events to a reader, using the same opaque Supabase UUID as
  /// [CrashReporter.identify] so a funnel drop-off and a crash report can
  /// be recognised as the same person. Never the email address.
  static void identify(String? userId) =>
      _run((analytics) => analytics.setUserId(id: userId));

  // ------------------------------------------------------------ paywall
  // The paywall is the one place in the app where the difference between
  // "saw it" and "did something about it" is worth money, so these four
  // are explicit rather than inferred from screen views.

  /// The paywall finished loading its prices and is on screen. Fired
  /// there rather than on navigation, so it counts readers who actually
  /// saw an offer — not ones who hit a spinner and left.
  ///
  /// [feature] is the [PaywallFeature] name the reader tapped to open it
  /// (`memory`, `customisation`, `general`…) — an enum constant, so it
  /// tells which locked surface converts without sending anything a
  /// reader wrote.
  static void paywallViewed({String feature = 'general'}) =>
      _log('paywall_viewed', {'feature': feature});

  /// A reader chose a plan. [plan] is a package identifier from
  /// RevenueCat (`monthly`, `annual`), never a price or a currency.
  static void paywallPlanSelected(String plan) =>
      _log('paywall_plan_selected', {'plan': plan});

  static void purchaseCompleted(String plan) =>
      _log('purchase_completed', {'plan': plan});

  /// [reason] is a coarse bucket — `cancelled`, `failed` — not the
  /// underlying store error, which can carry account detail.
  static void purchaseFailed(String reason) =>
      _log('purchase_failed', {'reason': reason});

  static void purchaseRestored() => _log('purchase_restored');

  // --------------------------------------------------------- onboarding

  /// The reader stepped out of the intro into the app itself. The
  /// denominator for every screen-view count above it — and, unlike the
  /// old flow, the only thing worth counting here: nothing in onboarding
  /// asks for anything any more, so there is no drop-off to attribute to
  /// a question.
  static void onboardingCompleted() => _log('onboarding_completed');

  static void _log(String name, [Map<String, Object>? parameters]) => _run(
    (analytics) => analytics.logEvent(name: name, parameters: parameters),
  );

  /// Every call is fire-and-forget and cannot fail the caller: analytics
  /// is the least important thing the app does, and a reader must never
  /// see a paywall break because a metric could not be recorded.
  static void _run(Future<void> Function(FirebaseAnalytics) action) {
    final analytics = _analytics;
    if (analytics == null) return;
    reportingFailure(
      action(analytics),
      source: 'AppAnalytics',
      message: 'Could not record an analytics event.',
    );
  }
}
