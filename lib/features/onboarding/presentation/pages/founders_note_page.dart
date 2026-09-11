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
    await showPaywallPopup(context, purchases: purchases, pricing: pricing);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
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
      progressStep: 3,
      // Inter itself resolves a monochrome glyph for the bare U+2764
      // codepoint, so `fontFamilyFallback` never even gets consulted —
      // this has to name the color emoji font directly as the primary
      // family to force it, unlike the other topContent emoji here,
      // none of which collide with a text-style glyph inside Inter.
      topContent: const Text(
        '❤️',
        style: TextStyle(fontSize: 96, fontFamily: 'Noto Color Emoji'),
      ),
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
