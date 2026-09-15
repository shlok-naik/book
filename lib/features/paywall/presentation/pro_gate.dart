import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/purchases/plan_controller.dart';
import '../../../core/purchases/purchases_service.dart';
import 'pages/paywall_page.dart';

/// The shared plumbing for a page that shows a faded, tap-to-unlock
/// preview to free readers and the real thing to pro ones — the stats
/// page's insights and journal, and the Memory tab.
///
/// [isProUnlocked] is decided the way every gate in the app decides it:
/// [PlanController.isPro] first (the live entitlement plus the debug
/// override), then — for a reader it says is free — a direct read of the
/// RevenueCat entitlement, which covers the moment between launch and
/// `PlanController.attach`'s first answer. It fails closed: unknown (not
/// yet checked, or the store unreachable) reads as "no", so a slow or
/// offline check never leaks a pro page to a free reader.
///
/// [unlockPro] opens the paywall on the chapter for [paywallFeature] and
/// rechecks on the way back, so a reader who just bought pro sees the page
/// unlock immediately rather than on their next visit.
mixin ProGateState<T extends StatefulWidget> on State<T> {
  /// Injection point for tests (a fake with fixed customer info); null in
  /// the app, where the real SDK wrapper is used.
  PurchasesService? get purchasesOverride;

  /// Which paywall chapter [unlockPro] opens on.
  PaywallFeature get paywallFeature;

  late final PurchasesService _purchases =
      purchasesOverride ?? const PurchasesService();

  bool _isProUnlocked = PlanController.isPro.value;

  /// True while an unlock tap has a paywall or entitlement check in
  /// flight, so a second tap can't stack another paywall on the first.
  bool _unlockBusy = false;

  bool get isProUnlocked => _isProUnlocked;
  bool get unlockBusy => _unlockBusy;

  @override
  void initState() {
    super.initState();
    PlanController.isPro.addListener(_onPlanChanged);
    unawaited(refreshProStatus());
  }

  @override
  void dispose() {
    PlanController.isPro.removeListener(_onPlanChanged);
    super.dispose();
  }

  void _onPlanChanged() => unawaited(refreshProStatus());

  Future<void> refreshProStatus() async {
    // The plan is read *after* the request: a purchase that lands while a
    // slow free-state check is still out sets the controller to pro, and a
    // value read before the await would let that stale answer lock the
    // page again.
    final hasEntitlement = await _hasProEntitlement();
    final isPro = PlanController.isPro.value || hasEntitlement;
    if (!mounted || isPro == _isProUnlocked) return;
    setState(() => _isProUnlocked = isPro);
  }

  Future<bool> _hasProEntitlement() async {
    try {
      return _purchases.isPro(await _purchases.customerInfo);
    } on Object {
      // Includes an SDK that was never configured — see the mixin doc for
      // why an unknown entitlement means "not pro" here.
      return false;
    }
  }

  Future<void> unlockPro() async {
    if (_unlockBusy) return;
    setState(() => _unlockBusy = true);
    try {
      await showPaywallPopup(
        context,
        purchases: purchasesOverride,
        feature: paywallFeature,
      );
      if (mounted) await refreshProStatus();
    } finally {
      if (mounted) setState(() => _unlockBusy = false);
    }
  }
}
