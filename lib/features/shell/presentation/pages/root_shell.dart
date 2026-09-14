import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../logging/presentation/pages/home_page.dart';
import '../../../memory/presentation/pages/memory_page.dart';
import '../../../paywall/data/intro_offer_store.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../streaks/presentation/pages/stats_page.dart';
import '../widgets/bottom_switcher.dart';

/// Hosts the four top-level pages — memory, stats, library, and the
/// log — and switches between them with a floating glass tab bar.
///
/// Also a safety net for the pro paywall: [FoundersNotePage], the last
/// real screen of onboarding, already shows it once and marks
/// [IntroOfferStore] seen on the way there, so for a fresh install this
/// shell's own check below is a no-op. It only actually fires the popup
/// for an existing install that finished onboarding before the paywall
/// lived there, or for the rare reader whose [IntroOfferStore] write
/// never landed. Either way it never brings the popup up unprompted
/// more than once. Every later route to it is one the reader chose —
/// the "get cactus pro" row in settings, a pro-only command, or tapping
/// the Memory tab on the free plan (see [_selectTab]).
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

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  /// The "+" / log page is the default screen.
  int _index = 3;

  static const _memoryIndex = 0;
  static const _addIndex = 3;

  /// True while the Memory tab's entitlement check or paywall is up, so a
  /// second tap can't stack another paywall on top of the first.
  bool _checkingMemoryAccess = false;

  late final IntroOfferStore _introOffer =
      widget.introOffer ?? const IntroOfferStore();

  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  late final _pages = [
    const MemoryPage(),
    StatsPage(purchases: widget.purchases),
    const LibraryPage(),
    const HomePage(),
  ];

  /// Reloads are skipped when the app was only away briefly.
  static const _staleAfter = Duration(minutes: 1);
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlanController.isPro.addListener(_onPlanChanged);
    // Post-frame: the popup is a route push, and there is no navigator
    // to push onto until this shell has actually been mounted under one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeShowIntroOffer());
    });
  }

  /// Coming back to the app reloads the shelf and the goal: another device
  /// signed in to the same email may have changed them — or replaced the
  /// whole library when it was linked — while this one sat in the
  /// background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastRefresh) < _staleAfter) return;
    _lastRefresh = now;
    unawaited(LibraryScope.read(context).load());
    unawaited(GoalScope.read(context).load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlanController.isPro.removeListener(_onPlanChanged);
    super.dispose();
  }

  /// A reader who loses pro while looking at the Memory tab (the debug
  /// plan toggle, today) is moved off it rather than left on a page the
  /// free plan doesn't include.
  void _onPlanChanged() {
    if (!PlanController.isPro.value && _index == _memoryIndex && mounted) {
      setState(() => _index = _addIndex);
    }
  }

  /// Switches tabs, except that the Memory tab is a cactus pro page: on
  /// the free plan, tapping it opens the paywall instead, and the reader
  /// stays on the tab they were on.
  ///
  /// Access is decided the way the rest of the app decides it —
  /// [PlanController.isPro] first, which is what gates `remember` and
  /// `recommend` on the add tab — and then, for a reader it says is free,
  /// the real RevenueCat entitlement, so a paying subscriber is never
  /// shown a paywall for a page they bought. If that check itself fails
  /// (offline, store unavailable) the paywall shows: from there a
  /// subscriber can restore, whereas silently opening a pro page for
  /// everyone whenever the store is unreachable would not be a gate at all.
  ///
  /// If the reader buys pro from that paywall, they land on Memory.
  Future<void> _selectTab(int next) async {
    if (next != _memoryIndex || PlanController.isPro.value) {
      setState(() => _index = next);
      return;
    }
    if (_checkingMemoryAccess) return;
    _checkingMemoryAccess = true;
    try {
      if (await _hasProEntitlement()) {
        if (mounted) setState(() => _index = _memoryIndex);
        return;
      }
      if (!mounted) return;
      await showPaywallPopup(context, purchases: widget.purchases);
      if (mounted && await _hasProEntitlement()) {
        setState(() => _index = _memoryIndex);
      }
    } finally {
      _checkingMemoryAccess = false;
    }
  }

  Future<bool> _hasProEntitlement() async {
    try {
      return _purchases.isPro(await _purchases.customerInfo);
    } on Object {
      // Includes an SDK that was never configured — see the doc comment on
      // [_selectTab] for why an unknown entitlement means "not pro" here.
      return false;
    }
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
                  onChanged: (i) => unawaited(_selectTab(i)),
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
