import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../logging/presentation/pages/home_page.dart';
import '../../../memory/presentation/pages/memory_page.dart';
import '../../../paywall/data/intro_offer_store.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../streaks/presentation/pages/streaks_page.dart';
import '../widgets/bottom_switcher.dart';

/// Hosts the four top-level pages — memory, streaks, library, and the
/// log — and switches between them with a floating glass tab bar.
///
/// Also the app's front door, now that there is no onboarding in front
/// of it: on the very first launch after install it presents the pro
/// paywall once, as a dismissible popup, and never brings it up
/// unprompted again. Every later route to it is one the reader chose —
/// the "get cactus pro" row in settings, or a pro-only command.
class RootShell extends StatefulWidget {
  const RootShell({super.key, this.introOffer, this.purchases});

  /// Injection point for tests: a fake flag store, so a test can decide
  /// whether the intro popup is due without touching device storage.
  final IntroOfferStore? introOffer;

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  /// The "+" / log page is the default screen.
  int _index = 3;

  late final IntroOfferStore _introOffer =
      widget.introOffer ?? const IntroOfferStore();

  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  static const _pages = [
    MemoryPage(),
    StreaksPage(),
    LibraryPage(),
    HomePage(),
  ];

  @override
  void initState() {
    super.initState();
    // Post-frame: the popup is a route push, and there is no navigator
    // to push onto until this shell has actually been mounted under one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeShowIntroOffer());
    });
  }

  /// Shows the paywall once per install, to readers who don't already
  /// have pro.
  ///
  /// Every check below fails *closed* — a store that can't be read, an
  /// entitlement that can't be fetched, and a reader who already paid
  /// all resolve to "don't show it". Missing the offer costs one
  /// conversion; showing a paywall to a paying subscriber, or on every
  /// launch, costs their goodwill.
  Future<void> _maybeShowIntroOffer() async {
    if (PlanController.isPro.value) return;
    if (await _introOffer.hasSeen()) return;

    try {
      if (_purchases.isPro(await _purchases.customerInfo)) return;
    } on PurchasesException {
      // Entitlements unknown — see the doc comment: don't risk it.
      return;
    }
    if (!mounted) return;

    // Marked before it is shown, not after it is dismissed: a reader who
    // force-quits while looking at it has still seen it.
    await _introOffer.markSeen();
    if (!mounted) return;
    await showPaywallPopup(context, purchases: widget.purchases);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        IndexedStack(index: _index, children: _pages),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.md,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSwitcher(
                  index: _index,
                  onChanged: (i) => setState(() => _index = i),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'cactus',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 15,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
