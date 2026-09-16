import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../logging/presentation/pages/home_page.dart';
import '../../../memory/presentation/pages/memory_page.dart';
import '../../../paywall/data/intro_offer_store.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../search/presentation/pages/search_page.dart';
import '../../../streaks/presentation/pages/stats_page.dart';
import '../start_page_controller.dart';
import '../widgets/bottom_switcher.dart';

/// Hosts the four top-level pages — search, stats, library, and the
/// log — and switches between them with a floating glass tab bar. Which
/// one it opens on is the reader's choice ([StartPageController]).
///
/// Also a safety net for the pro paywall: [FoundersNotePage], the last
/// real screen of onboarding, already shows it once and marks
/// [IntroOfferStore] seen on the way there, so for a fresh install this
/// shell's own check below is a no-op. It only actually fires the popup
/// for an existing install that finished onboarding before the paywall
/// lived there, or for the rare reader whose [IntroOfferStore] write
/// never landed. Either way it never brings the popup up unprompted
/// more than once. Every later route to it is one the reader chose —
/// the "get cactus pro" row in settings, a pro-only command, or tapping a
/// locked preview (the memory page's, the stats page's).
///
/// Memory is no longer a tab: it opens from settings' profile section, or
/// by typing a bare `memory` on the add tab ([openMemoryPage]).
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
  /// Where the reader chose to start — the add tab unless they changed it.
  int _index = switch (StartPageController.page.value) {
    StartPage.search => 0,
    StartPage.library => 2,
    StartPage.add => 3,
  };

  late final IntroOfferStore _introOffer =
      widget.introOffer ?? const IntroOfferStore();

  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  late final _pages = [
    SearchPage(resetSignal: _leftSearch),
    StatsPage(purchases: widget.purchases),
    const LibraryPage(),
    HomePage(
      onOpenMemory: () =>
          unawaited(openMemoryPage(context, purchases: widget.purchases)),
    ),
  ];

  /// Tabs that have been opened at least once. A tab is built the first
  /// time it's shown and kept alive after, rather than all four at launch:
  /// the stats tab starts their own fetches and entitlement
  /// checks on mount (the year's journal a second time, alongside the add
  /// tab's streak), and every mounted tab rebuilds on every shelf change
  /// whether it's visible or not.
  late final _visited = <int>{_index};

  /// Reloads are skipped when the app was only away briefly.
  static const _staleAfter = Duration(minutes: 1);
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Post-frame: the popup is a route push, and there is no navigator
    // to push onto until this shell has actually been mounted under one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The add tab shows the currently-reading book and goal progress from
      // the shelf, so the shelf loads at launch whichever tab mounts first.
      final library = LibraryScope.read(context);
      if (!library.hasLoaded) unawaited(library.load());
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
    _leftSearch.dispose();
    super.dispose();
  }

  /// Switches tabs. Every tab opens for every reader — the pro-only ones
  /// gate their own contents (see the class doc).
  /// Tells the search tab the reader left it, so it clears.
  final _leftSearch = ValueNotifier(0);

  void _selectTab(int next) {
    if (!mounted || next == _index) return;
    if (_index == 0) _leftSearch.value++;
    setState(() {
      _index = next;
      _visited.add(next);
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
        IndexedStack(
          index: _index,
          children: [
            for (final (i, page) in _pages.indexed)
              // Hidden tabs keep their state but stop animating.
              TickerMode(
                enabled: i == _index,
                child: _visited.contains(i) ? page : const SizedBox.shrink(),
              ),
          ],
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.md,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSwitcher(index: _index, onChanged: _selectTab),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'cactus',
                  style: context.fonts.interface(
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
