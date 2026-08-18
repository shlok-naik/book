/// The two prices the paywall offers, plus the validation the UI needs
/// before it can render them.
///
/// Prices arrive from a store/billing SDK in production, which means
/// they can be missing, zero, negative, or NaN when a fetch half-fails
/// — so the paywall never reads these fields without checking
/// [isValid] first, and falls back to an explicit "unavailable" state
/// rather than rendering `$NaN/mo` or a nonsense discount.
class PaywallPricing {
  const PaywallPricing({
    required this.monthlyPerMonth,
    required this.yearlyPerYear,
  });

  /// What the monthly plan costs per month.
  final double monthlyPerMonth;

  /// What the yearly plan costs per year — divided down for display, so
  /// both cards can quote a comparable per-month figure.
  final double yearlyPerYear;

  /// Stand-in used until real billing is wired up.
  static const placeholder = PaywallPricing(
    monthlyPerMonth: 4.99,
    yearlyPerYear: 40,
  );

  double get yearlyPerMonth => yearlyPerYear / 12;

  /// Both prices have to be real, finite, positive numbers. Anything
  /// else (a failed fetch leaving zeros, a parse producing NaN, a
  /// negative from a bad promo calculation) means we can't show a
  /// price at all.
  bool get isValid =>
      monthlyPerMonth.isFinite &&
      yearlyPerYear.isFinite &&
      monthlyPerMonth > 0 &&
      yearlyPerYear > 0;

  /// How much cheaper a year of the yearly plan is than twelve months
  /// of the monthly one, rounded to whole percent.
  ///
  /// Null whenever there's nothing honest to claim — invalid prices, or
  /// a yearly plan that isn't actually a saving. The savings tag is
  /// hidden in that case rather than showing "save 0%" or, worse, a
  /// negative "saving".
  int? get savingsPercent {
    if (!isValid) return null;
    final twelveMonths = monthlyPerMonth * 12;
    if (yearlyPerYear >= twelveMonths) return null;
    final percent = ((1 - yearlyPerYear / twelveMonths) * 100).round();
    return percent <= 0 ? null : percent;
  }
}
