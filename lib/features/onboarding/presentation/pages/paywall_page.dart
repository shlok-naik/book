import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show Package;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart'
    show PaywallResult;

import '../../../../core/purchases/entitlements.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/dotted_background.dart';
import '../../domain/paywall_pricing.dart';
import '../widgets/soft_pill_button.dart';
import 'one_more_thing_page.dart';
import 'purchase_thanks_page.dart';

/// First finish-category screen: sprung right after an account exists
/// (new sign-up or a returning sign-in). "join now" and "start free
/// trial" both purchase a real RevenueCat [Package] — see
/// [PurchasesService] — and only move on to [OneMoreThingPage] once
/// [PurchasesService.isPro] confirms [Entitlements.cactusPro] is
/// actually active, rather than assuming a successful purchase implies
/// entitlement.
///
/// ## Layout
///
/// Top-to-bottom: header, headline, a swipeable set of book "chapters"
/// — each one a feature, framed as a page the reader turns rather than
/// a list they skim — filling every bit of room left over between the
/// headline and the pricing cards, the CTA, and "not sure yet" below
/// it. The [_Metrics] scale factor is what keeps the proportions steady
/// from a small phone to a tablet without anything overflowing.
///
/// ## Component reuse
///
/// * the chapters are plain, real pages in a [PageView] — turned by
///   swipe rather than an automatic marquee, so nothing is cut off at
///   the edge and a reader sets their own pace;
/// * "join now" and "start free trial" (inside the sheet) are both
///   [SoftPillButton], the pill treatment every other onboarding
///   button wears — the CTA doesn't need a shape of its own to stand
///   out, just to be the only pill on screen;
/// * "not sure yet" and "restore purchases" are plain text links
///   rather than more pills — the close button already covers "I
///   don't want this", so they only need to be findable, not as
///   visually loud as "join now";
/// * colors come from [AppColors] and spacing/radii from
///   [AppSpacing] / [AppRadius], so the screen follows the reader's
///   light/dark choice like the rest of the flow.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.pricing, this.purchases});

  /// Prices to display. Null — the normal production path — has
  /// [_PaywallPageState] fetch the current RevenueCat offering itself
  /// and derive real prices from its `monthly`/`yearly` packages (see
  /// [PurchasesService.currentOffering] and [PackageIds]). Passing this
  /// directly skips that fetch entirely — tests, and any call site that
  /// already knows the price, use it this way.
  final PaywallPricing? pricing;

  /// Injection point for tests: a fake wrapping fake offerings/purchase
  /// results instead of the real RevenueCat SDK. Null in the app —
  /// [PurchasesService.configure] has already set up the real SDK by
  /// the time this page is ever pushed (see `main.dart`).
  final PurchasesService? purchases;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

enum _Plan { monthly, yearly }

/// Everything that scales with viewport height, resolved once per
/// build so the sections can't drift apart from each other.
///
/// [scale] is keyed to a ~760pt reference viewport and clamped, so a
/// short screen tightens uniformly rather than letting one section
/// collapse while its neighbour keeps full size.
class _Metrics {
  _Metrics(double height) : scale = (height / 760).clamp(0.82, 1.0);

  final double scale;

  double get gapSm => AppSpacing.sm * scale;
  double get gapMd => AppSpacing.md * scale;
  double get gapLg => AppSpacing.lg * scale;

  /// Both pricing cards are pinned to this height, so selecting one
  /// changes only its *width* — the row never reflows vertically.
  double get pricingCardHeight => 104 * scale;

  /// Vertical room reserved above the pricing row for the savings tag,
  /// which is deliberately positioned outside the card's top edge.
  double get badgeOverhang => 12 * scale;
}

class _PaywallPageState extends State<PaywallPage> {
  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  /// What [_PricingRow]/[_PricingUnavailable] render. Starts from
  /// [widget.pricing] if the caller supplied one (skipping the fetch
  /// below entirely); otherwise starts as the placeholder and is
  /// replaced once [_loadOffering] resolves, same as any other
  /// loading-then-loaded state in the app.
  late PaywallPricing _pricing = widget.pricing ?? PaywallPricing.placeholder;

  /// The real packages behind [_pricing] — null until [_loadOffering]
  /// finds them (or forever, if the caller supplied [widget.pricing]
  /// directly and there's nothing to purchase against).
  Package? _monthlyPackage;

  /// The trial-bearing yearly product ([PackageIds.yearly]) — bought
  /// only via [_startFreeTrial], never via "join now" (see
  /// [_yearlyNoTrialPackage]).
  Package? _yearlyPackage;

  /// The trial-free yearly product ([PackageIds.yearlyNoTrial]) — what
  /// "join now" actually buys when yearly is selected. Optional: a
  /// dashboard that hasn't set this up yet falls back to
  /// [_yearlyPackage] in [_purchasePlan] rather than blocking checkout,
  /// which does mean "join now" would grant the trial in that
  /// fallback case — but that's the same behavior the app had before
  /// this product existed, not a regression.
  Package? _yearlyNoTrialPackage;

  /// Yearly leads on load — it's the better value, and the savings tag
  /// only has something to say while it's the selected plan.
  _Plan _plan = _Plan.yearly;

  bool _busy = false;
  String? _error;

  static const _unavailable = PaywallPricing(
    monthlyPerMonth: 0,
    yearlyPerYear: 0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.pricing == null) _loadOffering();
  }

  Future<void> _loadOffering() async {
    try {
      final offering = await _purchases.currentOffering;
      final monthly = offering?.getPackage(PackageIds.monthly);
      final yearly = offering?.getPackage(PackageIds.yearly);
      final yearlyNoTrial = offering?.getPackage(PackageIds.yearlyNoTrial);
      if (!mounted) return;
      setState(() {
        _monthlyPackage = monthly;
        _yearlyPackage = yearly;
        _yearlyNoTrialPackage = yearlyNoTrial;
        // Both packages have to actually be there — a dashboard
        // missing either one isn't a state the pricing row/toggle can
        // render honestly, so it falls back to the same "couldn't
        // load pricing" state as a network failure.
        _pricing = (monthly != null && yearly != null)
            ? PaywallPricing(
                monthlyPerMonth: monthly.storeProduct.price,
                yearlyPerYear: yearly.storeProduct.price,
              )
            : _unavailable;
      });
    } on PurchasesException {
      if (!mounted) return;
      setState(() => _pricing = _unavailable);
    }
  }

  void _continue() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OneMoreThingPage()));
  }

  /// Same destination as [_continue], but by way of [PurchaseThanksPage]
  /// first — only a genuine new purchase earns the "welcome … PRO"
  /// celebration; restoring a past purchase or backing out entirely
  /// still goes straight through [_continue].
  void _continueAfterPurchase() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseThanksPage(onContinue: _continue),
      ),
    );
  }

  void _selectPlan(_Plan plan) => setState(() => _plan = plan);

  /// Buys whichever package [plan] resolves to — the monthly product,
  /// or [_yearlyNoTrialPackage] (never [_yearlyPackage]) for yearly, so
  /// "join now" can't hand an eligible reader the trial [_startFreeTrial]
  /// is meant to be the only path to. Falls back to [_yearlyPackage] if
  /// the no-trial product hasn't been set up yet — see its doc comment.
  Future<void> _purchasePlan(_Plan plan) {
    final package = switch (plan) {
      _Plan.monthly => _monthlyPackage,
      _Plan.yearly => _yearlyNoTrialPackage ?? _yearlyPackage,
    };
    return _purchasePackage(package);
  }

  /// The one purchase [SoftPillButton] the "not sure yet" sheet
  /// offers, and the only path that ever buys [_yearlyPackage] — see
  /// its doc comment for why that has to stay separate from
  /// [_purchasePlan]'s yearly branch.
  Future<void> _startFreeTrial() => _purchasePackage(_yearlyPackage);

  /// Buys [package] and, only once [PurchasesService.isPro] confirms
  /// the purchase actually activated [Entitlements.cactusPro], moves
  /// on. A null package means [widget.pricing] was supplied directly
  /// with nothing real behind it (a test, a preview) — there's nothing
  /// to purchase, so this just moves on the way the page always did
  /// before billing existed.
  Future<void> _purchasePackage(Package? package) async {
    if (package == null) {
      _continue();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _purchases.purchase(package);
      if (!mounted) return;
      if (_purchases.isPro(info)) {
        _continueAfterPurchase();
        return;
      }
      setState(() {
        _busy = false;
        _error =
            "That went through, but PRO isn't active yet — try "
            'restoring purchases.';
      });
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      // A reader backing out of the native sheet isn't an error worth
      // surfacing — just quietly re-enable the button.
      if (!error.userCancelled) setState(() => _error = error.message);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _purchases.restore();
      if (!mounted) return;
      setState(() => _busy = false);
      if (_purchases.isPro(info)) {
        _continue();
      } else {
        setState(() => _error = 'No previous purchase found for this account.');
      }
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  /// The fallback for when this page's own pricing couldn't load —
  /// RevenueCat's own dashboard-configured paywall, which fetches and
  /// renders the offering itself rather than depending on the same
  /// [_loadOffering] call that just failed.
  Future<void> _viewHostedPaywall() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _purchases.presentPaywallIfNeeded();
      if (!mounted) return;
      setState(() => _busy = false);
      if (result == PaywallResult.purchased ||
          result == PaywallResult.restored) {
        _continue();
      }
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  /// The only place a trial is offered — or even mentioned. "join now"
  /// below never brings it up.
  void _showNotSureSheet() {
    final colors = context.colors;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'free trial',
              style: GoogleFonts.ebGaramond(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'full access to every feature for 3 days. after your trial '
              'ends, you continue on the yearly plan.',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SoftPillButton(
              label: 'start free trial',
              onPressed: () {
                Navigator.of(context).pop();
                // The only call site that ever buys `_yearlyPackage` —
                // see its doc comment for why "join now" deliberately
                // buys a separate, trial-free product instead.
                _startFreeTrial();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final priceable = _pricing.isValid;

    return Scaffold(
      backgroundColor: colors.background,
      body: DottedBackground(
        child: SafeArea(
          bottom: false,
          // A near-full-bleed card: only a sliver of a gap up top, so
          // the dotted background still reads behind the rounded
          // corners without this becoming a half-sheet.
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: ColoredBox(
                color: colors.surface,
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final m = _Metrics(constraints.maxHeight);

                      return Column(
                        children: [
                          _Header(onClose: _continue, metrics: m),
                          SizedBox(height: m.gapSm),
                          // Fills every bit of room left over between
                          // the headline and the commit block — this is
                          // the "empty middle" the old marquee-and-two-
                          // spacers layout used to leave behind, now
                          // doing double duty as the pitch itself.
                          Expanded(child: _ChapterPager(metrics: m)),
                          _CommitBlock(
                            metrics: m,
                            pricing: _pricing,
                            priceable: priceable,
                            plan: _plan,
                            busy: _busy,
                            error: _error,
                            onSelectPlan: _selectPlan,
                            onNotSureYet: _showNotSureSheet,
                            onSubmit: (priceable && !_busy)
                                ? () => _purchasePlan(_plan)
                                : null,
                            onRestore: _busy ? null : _restore,
                            onViewHostedPaywall: (!priceable && !_busy)
                                ? _viewHostedPaywall
                                : null,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wordmark + PRO badge + close, then the headline beneath — the hook
/// that has three seconds to convince the reader this is worth paying
/// for, so it names the concrete thing PRO does rather than gesturing
/// at it with a quote.
class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.metrics});

  final VoidCallback onClose;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            metrics.gapMd,
            AppSpacing.sm,
            0,
          ),
          child: Row(
            // Centered so the badge sits level with the middle of the
            // wordmark rather than riding its baseline.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'cactus',
                style: GoogleFonts.ebGaramond(
                  fontSize: 32 * metrics.scale,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryText,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'PRO',
                  style: GoogleFonts.inter(
                    fontSize: 13 * metrics.scale,
                    fontWeight: FontWeight.w800,
                    color: colors.background,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // IconButton keeps the 48x48 minimum tap target even
              // though the glyph is small.
              IconButton(
                onPressed: onClose,
                tooltip: 'close',
                icon: Icon(Icons.close, color: colors.secondaryText),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.gapLg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            'just say it. cactus handles the rest.',
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 26 * metrics.scale,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: colors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

/// One "chapter" per feature. [body] is the real pitch, kept to two
/// short sentences — a book's wide margins only stay airy if the copy
/// itself stays brief. [filler] is one line of plain placeholder text,
/// the same role Lorem Ipsum plays in a print layout, just enough to
/// give the page a second line of rhythm without running long.
typedef _Chapter = ({String roman, String title, String body, String filler});

const _chapters = <_Chapter>[
  (
    roman: 'I',
    title: 'Converse & Express',
    body:
        'Interact with your library using your own words. Express your '
        'emotions, and discover exactly what you are looking for next.',
    filler: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
  ),
  (
    roman: 'II',
    title: 'A Mind of Its Own',
    body:
        'Powered by advanced AI with long-term memory. It remembers '
        'your preferences and conversations, so you never repeat '
        'yourself.',
    filler: 'Duis aute irure dolor in reprehenderit in voluptate velit.',
  ),
  (
    roman: 'III',
    title: 'The Perfect Match',
    body:
        'Discover your next great story. Get tailored recommendations '
        'built from your conversational history.',
    filler: 'Sed ut perspiciatis unde omnis iste natus error sit.',
  ),
];

/// The pitch, told as chapters rather than skimmed as a feature list —
/// swipe left to turn the page onto the next one. A row of dots below
/// tracks which chapter is open, the same way a book's progress is felt
/// by the thickness of the pages left in either hand.
class _ChapterPager extends StatefulWidget {
  const _ChapterPager({required this.metrics});

  final _Metrics metrics;

  @override
  State<_ChapterPager> createState() => _ChapterPagerState();
}

class _ChapterPagerState extends State<_ChapterPager> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _chapters.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => _ChapterTransition(
              controller: _controller,
              index: index,
              fallbackPage: _page,
              child: _ChapterPage(
                chapter: _chapters[index],
                metrics: widget.metrics,
              ),
            ),
          ),
        ),
        SizedBox(height: widget.metrics.gapSm),
        _PageDots(count: _chapters.length, index: _page),
      ],
    );
  }
}

/// A gentler substitute for [PageView]'s default hard slide: as a
/// chapter scrolls away from center it fades and shrinks slightly
/// rather than just translating, so turning the page reads as a soft
/// crossfade native to a dark digital screen instead of a literal
/// paper-curl.
class _ChapterTransition extends StatelessWidget {
  const _ChapterTransition({
    required this.controller,
    required this.index,
    required this.fallbackPage,
    required this.child,
  });

  final PageController controller;
  final int index;

  /// Used only before the controller has attached to its
  /// [PageView] and gained a scroll position — from then on
  /// [controller.page] is authoritative.
  final int fallbackPage;

  final Widget child;

  static const _maxScaleDrop = 0.08;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? (controller.page ?? fallbackPage.toDouble())
            : fallbackPage.toDouble();
        final distance = (page - index).abs().clamp(0.0, 1.0);

        return Opacity(
          opacity: 1 - distance,
          child: Transform.scale(
            scale: 1 - (distance * _maxScaleDrop),
            child: child,
          ),
        );
      },
    );
  }
}

/// A single chapter, framed like a museum exhibit card rather than a
/// bare page of text: a thin hairline border and a background tone
/// lifted off the surface behind it (the same background-on-surface
/// contrast used throughout onboarding), with wide padding on every
/// side so the frame itself supplies the negative space a page of
/// running text needs to feel unhurried rather than cramped.
///
/// Inside: roman numeral, centered title, a short rule, then two brief
/// paragraphs — set in [GoogleFonts.libreBaskerville], the book trade's
/// own standard face, rather than the [Inter]/[GoogleFonts.ebGaramond]
/// mix the rest of onboarding wears. Content starts right under the top
/// edge of the frame rather than centering within it. Wrapped to scroll
/// rather than overflow on the rare viewport too short to fit it all.
class _ChapterPage extends StatelessWidget {
  const _ChapterPage({required this.chapter, required this.metrics});

  final _Chapter chapter;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Darker than the secondaryText this page otherwise reaches for —
    // a soft charcoal rather than pure black, but dark enough that a
    // whole paragraph of it stays comfortable to read.
    final bodyColor = Color.alphaBlend(
      colors.primaryText.withValues(alpha: 0.82),
      colors.background,
    );
    final bodyStyle = GoogleFonts.libreBaskerville(
      fontSize: 15 * metrics.scale,
      height: 1.7,
      color: bodyColor,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: metrics.gapSm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.divider),
          // A soft, highly diffused shadow — only in light mode, where
          // it reads against the surface behind it; in dark mode a
          // shadow this faint would be invisible, so the border alone
          // carries the separation, same rule SoftPillShell follows.
          boxShadow: isLight
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: metrics.gapLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'chapter ${chapter.roman}',
                textAlign: TextAlign.center,
                style: GoogleFonts.libreBaskerville(
                  fontSize: 13 * metrics.scale,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1.5,
                  color: colors.secondaryText,
                ),
              ),
              SizedBox(height: metrics.gapSm),
              Text(
                chapter.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.libreBaskerville(
                  fontSize: 22 * metrics.scale,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              SizedBox(height: metrics.gapMd),
              Container(width: 32, height: 1, color: colors.divider),
              SizedBox(height: metrics.gapMd),
              Text(
                chapter.body,
                textAlign: TextAlign.justify,
                style: bodyStyle,
              ),
              SizedBox(height: metrics.gapMd),
              Text(
                chapter.filler,
                textAlign: TextAlign.justify,
                style: bodyStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chapter position indicator: a wide pill for the open chapter,
/// small dots for the rest — the same "current page is longer" shape
/// as the pricing row above claiming more width for the selected plan.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  static const _dotSize = 6.0;
  static const _activeWidth = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? _activeWidth : _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: i == index ? colors.accent : colors.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}

/// Pricing cards, any purchase error, "not sure yet"/"restore
/// purchases", and the CTA — the part of the screen that asks for a
/// decision, pinned together at the bottom.
class _CommitBlock extends StatelessWidget {
  const _CommitBlock({
    required this.metrics,
    required this.pricing,
    required this.priceable,
    required this.plan,
    required this.busy,
    required this.error,
    required this.onSelectPlan,
    required this.onNotSureYet,
    required this.onSubmit,
    required this.onRestore,
    required this.onViewHostedPaywall,
  });

  final _Metrics metrics;
  final PaywallPricing pricing;
  final bool priceable;
  final _Plan plan;
  final bool busy;
  final String? error;
  final ValueChanged<_Plan> onSelectPlan;
  final VoidCallback onNotSureYet;
  final VoidCallback? onSubmit;
  final VoidCallback? onRestore;
  final VoidCallback? onViewHostedPaywall;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        metrics.gapLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (priceable)
            _PricingRow(
              metrics: metrics,
              pricing: pricing,
              plan: plan,
              onSelectPlan: onSelectPlan,
            )
          else
            _PricingUnavailable(onViewPlans: onViewHostedPaywall),
          if (error != null) ...[
            SizedBox(height: metrics.gapSm),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13 * metrics.scale,
                color: colors.secondaryText,
              ),
            ),
          ],
          SizedBox(height: metrics.gapMd),
          SoftPillButton(
            label: busy ? 'joining…' : 'join now',
            onPressed: onSubmit,
          ),
          SizedBox(height: metrics.gapSm),
          // Deliberately not the trial CTA — that one only lives inside
          // the sheet this opens. Plain text links rather than more
          // pills: the close button up top already covers "I don't
          // want this", so these only need to be findable, not as
          // visually loud as "join now".
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: onNotSureYet,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.secondaryText,
                  ),
                  child: Text(
                    'not sure yet',
                    style: GoogleFonts.inter(
                      fontSize: 14 * metrics.scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '·',
                  style: GoogleFonts.inter(
                    fontSize: 14 * metrics.scale,
                    color: colors.divider,
                  ),
                ),
                TextButton(
                  onPressed: onRestore,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.secondaryText,
                  ),
                  child: Text(
                    'restore purchases',
                    style: GoogleFonts.inter(
                      fontSize: 14 * metrics.scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two plans, touching, filling the row exactly.
///
/// Widths are computed from the row's own width rather than left to
/// `Expanded`, for two reasons: the split has to *animate* when
/// selection moves (flex factors snap), and the two widths must always
/// sum to exactly the available width so the cards stay flush with no
/// seam or overflow.
class _PricingRow extends StatelessWidget {
  const _PricingRow({
    required this.metrics,
    required this.pricing,
    required this.plan,
    required this.onSelectPlan,
  });

  final _Metrics metrics;
  final PaywallPricing pricing;
  final _Plan plan;
  final ValueChanged<_Plan> onSelectPlan;

  /// Share of the row the selected card claims. The other card takes
  /// the remainder, so the pair always spans the full width.
  static const _selectedShare = 0.56;

  @override
  Widget build(BuildContext context) {
    final savings = pricing.savingsPercent;

    return Padding(
      // Reserves room for the savings tag, which sits above the card's
      // top edge and would otherwise be clipped by whatever is above.
      padding: EdgeInsets.only(top: metrics.badgeOverhang),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final total = constraints.maxWidth;
          final selectedWidth = total * _selectedShare;
          final unselectedWidth = total - selectedWidth;
          final monthlySelected = plan == _Plan.monthly;

          return Row(
            children: [
              _PricingCard(
                label: 'monthly',
                priceLine: '\$${pricing.monthlyPerMonth.toStringAsFixed(2)}/mo',
                selected: monthlySelected,
                width: monthlySelected ? selectedWidth : unselectedWidth,
                height: metrics.pricingCardHeight,
                // Square where it meets its neighbour, rounded on the
                // outside — the two read as one connected control.
                radius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.md),
                ),
                onTap: () => onSelectPlan(_Plan.monthly),
                metrics: metrics,
              ),
              _PricingCard(
                label: 'yearly',
                priceLine: '\$${pricing.yearlyPerMonth.toStringAsFixed(2)}/mo',
                subLine: '\$${pricing.yearlyPerYear.toStringAsFixed(0)}/yr',
                // Hidden unless the saving is both real and this card is
                // the one being emphasised.
                badge: savings == null ? null : 'save $savings%',
                selected: !monthlySelected,
                width: monthlySelected ? unselectedWidth : selectedWidth,
                height: metrics.pricingCardHeight,
                radius: const BorderRadius.horizontal(
                  right: Radius.circular(AppRadius.md),
                ),
                onTap: () => onSelectPlan(_Plan.yearly),
                metrics: metrics,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.label,
    required this.priceLine,
    required this.selected,
    required this.width,
    required this.height,
    required this.radius,
    required this.onTap,
    required this.metrics,
    this.subLine,
    this.badge,
  });

  final String label;
  final String priceLine;
  final String? subLine;
  final String? badge;
  final bool selected;
  final double width;
  final double height;
  final BorderRadius radius;
  final VoidCallback onTap;
  final _Metrics metrics;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Selected keeps full-strength text; unselected drops back so the
    // emphasis reads at a glance. Alphas stay above the 4.5:1 contrast
    // floor against `background` in both themes.
    final labelColor = selected
        ? colors.secondaryText
        : colors.secondaryText.withValues(alpha: 0.55);
    final priceColor = selected
        ? colors.primaryText
        : colors.primaryText.withValues(alpha: 0.45);
    final subColor = colors.secondaryText.withValues(
      alpha: selected ? 0.8 : 0.45,
    );

    final semanticPrice = subLine == null
        ? priceLine
        : '$priceLine, billed $subLine';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label plan, $semanticPrice${badge != null && selected ? ', $badge' : ''}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            // The savings tag deliberately overhangs the top edge.
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOut,
                width: width,
                height: height,
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.gapMd,
                  vertical: metrics.gapSm,
                ),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? colors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: _duration,
                      style: GoogleFonts.inter(
                        fontSize: 13 * metrics.scale,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      child: Text(label),
                    ),
                    SizedBox(height: metrics.gapSm),
                    // scaleDown keeps the price legible-but-unclipped
                    // mid-animation, while the card is still narrowing.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: _duration,
                        style: GoogleFonts.inter(
                          fontSize: (selected ? 22 : 16) * metrics.scale,
                          fontWeight: FontWeight.w700,
                          color: priceColor,
                        ),
                        child: Text(priceLine),
                      ),
                    ),
                    if (subLine != null) ...[
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedDefaultTextStyle(
                          duration: _duration,
                          style: GoogleFonts.inter(
                            fontSize: 12 * metrics.scale,
                            color: subColor,
                          ),
                          child: Text(subLine!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null && selected)
                Positioned(
                  top: -metrics.badgeOverhang,
                  right: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      badge!,
                      style: GoogleFonts.inter(
                        fontSize: 11 * metrics.scale,
                        fontWeight: FontWeight.w700,
                        color: colors.background,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the pricing cards when [PaywallPricing.isValid] is
/// false — a missing or malformed price is surfaced plainly rather than
/// rendered as `$NaN/mo`, and the CTA above is disabled alongside it.
/// [onViewPlans], when set, offers RevenueCat's own dashboard-hosted
/// paywall as a working fallback — it fetches and renders the offering
/// itself, sidestepping whatever made this page's own fetch fail.
class _PricingUnavailable extends StatelessWidget {
  const _PricingUnavailable({this.onViewPlans});

  final VoidCallback? onViewPlans;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: colors.secondaryText),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    "we couldn't load pricing right now. check your "
                    'connection and try again in a moment.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
            if (onViewPlans != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onViewPlans,
                  style: TextButton.styleFrom(foregroundColor: colors.accent),
                  child: Text(
                    'view plans',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
