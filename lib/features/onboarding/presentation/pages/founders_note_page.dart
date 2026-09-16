import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/data/intro_offer_store.dart';
import '../../../paywall/domain/paywall_pricing.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'finish_page.dart';

/// Third finish-category screen — a short personal note, signed by
/// name, before the last "you're all set" beat.
///
/// "continue" shows the same one-time PRO paywall [RootShell] would
/// otherwise present on the reader's first visit to the app — see
/// [showPaywallPopup] — right here at the natural end of the tour,
/// while the reader is still paying attention. [IntroOfferStore] is
/// marked seen first, before the popup even opens (same reasoning as
/// `RootShell._maybeShowIntroOffer`: a reader who force-quits on it has
/// still seen it), so that later check never shows it a second time
/// this install. The reader reaches [FinishPage] whether they buy,
/// restore, or just close it — the paywall is a pitch, not a gate.
class FoundersNotePage extends StatelessWidget {
  const FoundersNotePage({
    super.key,
    this.purchases,
    this.pricing,
    this.introOffer,
  });

  /// Injection point for tests: a fake wrapping fake offerings/purchase
  /// results instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  /// Injection point for tests: skips [PaywallPage]'s own offering
  /// fetch entirely when supplied. Null in the app.
  final PaywallPricing? pricing;

  /// Injection point for tests: a fake flag store, so a test can watch
  /// the intro offer being marked seen without touching device storage.
  final IntroOfferStore? introOffer;

  Future<void> _continue(BuildContext context) async {
    await (introOffer ?? const IntroOfferStore()).markSeen();
    if (!context.mounted) return;
    // nextRoute, not a separate push once this awaited future resolves:
    // the popup's own future only completes after its pop transition
    // finishes, so a plain pop-then-push would flash this page back
    // into view for that transition's duration before FinishPage
    // appeared on top of it.
    await showPaywallPopup(
      context,
      purchases: purchases,
      pricing: pricing,
      nextRoute: () => MaterialPageRoute(
        settings: const RouteSettings(name: 'onboarding_finish'),
        builder: (_) => const FinishPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      topContent: const TourIcon(Icons.favorite_border),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'a note from the founder',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'i built cactus cuz every other tracker made reading feel '
            'like math homework (lol). thanks for giving it a try - i '
            'hope you love it as much as i do.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '- shlok',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'continue',
            onPressed: () => _continue(context),
          ),
        ],
      ),
    );
  }
}
