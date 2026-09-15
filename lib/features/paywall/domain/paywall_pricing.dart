/// The two prices the paywall offers, plus the validation the UI needs
/// before it can render them.
///
/// Prices arrive from a store/billing SDK in production, which means
/// they can be missing, zero, negative, or NaN when a fetch half-fails
/// — so the paywall never reads these fields without checking
/// [isValid] first, and falls back to an explicit "unavailable" state
/// rather than rendering `$NaN/mo` or a nonsense discount.
///
/// ## Display
///
/// The labels ([monthlyLabel], [yearlyPerMonthLabel], [yearlyLabel]) are
/// what the cards print. In production they are the store's own localized
/// strings — "£3.99", "3,99 €", "¥600" — carried straight from the
/// RevenueCat `StoreProduct`, never rebuilt here: the paywall used to
/// prefix a hardcoded `$` and round the yearly price to whole units, so a
/// UK reader saw "$40/yr" for a £39.99 plan. Showing the price the store
/// will actually charge is also what App Store review checks. The raw
/// numbers remain for validation and the savings maths only; the `$`
/// fallback exists solely for [placeholder] and tests that pass numbers.
class PaywallPricing {
  const PaywallPricing({
    required this.monthlyPerMonth,
    required this.yearlyPerYear,
    this.monthlyPriceString,
    this.yearlyPriceString,
    this.yearlyPerMonthString,
  });

  /// What the monthly plan costs per month.
  final double monthlyPerMonth;

  /// What the yearly plan costs per year — divided down for display, so
  /// both cards can quote a comparable per-month figure.
  final double yearlyPerYear;

  /// The store's localized monthly price (`StoreProduct.priceString`).
  final String? monthlyPriceString;

  /// The store's localized yearly price (`StoreProduct.priceString`).
  final String? yearlyPriceString;

  /// The store's localized per-month equivalent of the yearly plan
  /// (`StoreProduct.pricePerMonthString`), in the store's own rounding.
  final String? yearlyPerMonthString;

  /// Stand-in used until real billing is wired up.
  static const placeholder = PaywallPricing(
    monthlyPerMonth: 4.99,
    yearlyPerYear: 40,
  );

  double get yearlyPerMonth => yearlyPerYear / 12;

  String get monthlyLabel =>
      monthlyPriceString ?? '\$${monthlyPerMonth.toStringAsFixed(2)}';

  String get yearlyPerMonthLabel =>
      yearlyPerMonthString ?? '\$${yearlyPerMonth.toStringAsFixed(2)}';

  /// Unlike the old display, never rounded to whole units — "\$39.99",
  /// not "\$40".
  String get yearlyLabel =>
      yearlyPriceString ?? '\$${_trimZeroCents(yearlyPerYear)}';

  /// "40" for 40.00, "39.99" for 39.99.
  static String _trimZeroCents(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

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
