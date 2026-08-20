/// RevenueCat identifiers configured in the dashboard — kept in one
/// place so a typo can't silently split an entitlement/package check
/// from the string it's actually comparing against.
abstract final class Entitlements {
  /// The single paid tier the app offers. Gates everything the paywall
  /// sells: natural language, long-term memory, recommendations.
  static const cactusPro = 'cactus pro';
}

/// Package identifiers for the current offering — RevenueCat's built-in
/// package type identifiers (assigned automatically when a package is
/// added to an offering as "Monthly"/"Annual" rather than a custom
/// type), not the underlying store product ids (which can differ per
/// platform).
abstract final class PackageIds {
  static const monthly = r'$rc_monthly';

  /// The yearly product carrying the 3-day free trial — bought only
  /// from the "not sure yet" sheet's "start free trial" button, never
  /// from the main "join now" CTA (see [yearlyNoTrial]).
  static const yearly = r'$rc_annual';

  /// A second yearly product, priced identically but with no trial
  /// attached, added to the offering as a Custom package (RevenueCat
  /// allows only one package per built-in type like "Annual" in a
  /// single offering). This is what "join now" actually buys when
  /// yearly is selected — a trial is a property of the underlying
  /// product, not of which button was tapped, so the only way to keep
  /// "join now" from silently granting one to an eligible reader is to
  /// point it at a distinct, trial-free product entirely.
  static const yearlyNoTrial = 'yearly_no_trial';
}
