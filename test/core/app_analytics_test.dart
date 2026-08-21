import 'package:book/core/analytics/app_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same hazard as `CrashReporter`: `FirebaseAnalytics.instance` throws
/// synchronously when Firebase was never initialized. Analytics is
/// sprinkled through the paywall — the one screen where an exception
/// costs money — so every entry point has to be inert until `attach`
/// has run, and a test binding never runs `main`.
void main() {
  test('is not attached in a test binding', () {
    expect(AppAnalytics.isAttached, isFalse);
  });

  test('contributes no navigator observers until attached', () {
    // MaterialApp reads this on every build; a non-empty list here would
    // mean constructing a FirebaseAnalyticsObserver with no Firebase.
    expect(AppAnalytics.navigatorObservers, isEmpty);
  });

  test('every event is a no-op rather than a throw when unattached', () {
    expect(() {
      AppAnalytics.identify('some-user-id');
      AppAnalytics.identify(null);
      AppAnalytics.paywallViewed();
      AppAnalytics.paywallPlanSelected('yearly');
      AppAnalytics.purchaseCompleted('rc_annual');
      AppAnalytics.purchaseFailed('cancelled');
      AppAnalytics.purchaseRestored();
      AppAnalytics.onboardingCompleted();
    }, returnsNormally);
  });
}
