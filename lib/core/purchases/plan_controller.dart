import 'dart:async';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../diagnostics/app_logger.dart';
import 'entitlements.dart';
import 'purchases_service.dart';

/// Whether the app should behave as cactus pro — the one flag every
/// feature gate reads (`HomePage`'s natural-language path and
/// `remember`/`recommend`, the collection caps, the Memory tab, the stats
/// page's insights, settings' pro rows).
///
/// [isPro] is the reader's real RevenueCat [Entitlements.cactusPro]
/// entitlement. (It was once OR'd with a debug override; nothing reached it
/// any more, and a switch that grants pro has no business in a release
/// build.) Tests set [isPro] directly. Mirrors `ThemeController`'s shape.
///
/// It used to be *only* that debug override — nothing ever wrote the real
/// entitlement into it — so every gate reading it treated a paying
/// subscriber as free: their sentences went to the manual parser instead
/// of the AI, `remember` refused them, and the collection caps applied.
/// [attach] is what closes that gap; call it once from `_bootstrap`,
/// after `PurchasesService.configure`.
///
/// Fails closed: until the first entitlement read lands — or forever, if
/// the store can't be reached and RevenueCat has no cached customer info
/// — the entitlement half reads false. A subscriber who launches offline
/// for the very first time sees free-plan gates until the store answers;
/// RevenueCat caches customer info on the device, so that is rare after
/// the first successful launch.
class PlanController {
  PlanController._();

  /// The effective plan. Writable for tests (`isPro.value = true` is the
  /// long-standing way the suite pretends to be pro); in the app only the
  /// entitlement updates below write it.
  static final ValueNotifier<bool> isPro = ValueNotifier(false);

  static bool _entitled = false;
  static StreamSubscription<CustomerInfo>? _subscription;

  /// Whether the real store entitlement is active — for UI that must not
  /// lie about an actual subscription (the membership card's PRO badge,
  /// "manage subscription"), even while a test has set [isPro].
  static bool get isEntitled => _entitled;

  /// Records a fresh entitlement read. Called by [attach]'s stream, and by
  /// any surface that just fetched [CustomerInfo] itself (settings'
  /// refresh, the paywall after a purchase) so the whole app flips at
  /// once instead of waiting for RevenueCat's listener to fire.
  static void updateEntitlement(bool entitled) {
    _entitled = entitled;
    _publish();
  }

  /// Seeds the entitlement from the store and subscribes to every later
  /// change — purchases, restores, renewals, expiries and refunds, from
  /// this device or another, since RevenueCat pushes those from its own
  /// servers. Idempotent. Never throws: a store that can't be read leaves
  /// the reader on the free plan (see the class doc on failing closed).
  static Future<void> attach(PurchasesService purchases) async {
    if (_subscription != null) return;
    _subscription = PurchasesService.customerInfoStream.listen(
      (info) => updateEntitlement(purchases.isPro(info)),
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'PlanController',
        'The customer info stream failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    try {
      updateEntitlement(purchases.isPro(await purchases.customerInfo));
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'PlanController',
        'Could not read the entitlement at startup; treating as free.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Test-only: back to a fresh, detached, free state.
  @visibleForTesting
  static Future<void> reset() async {
    await _subscription?.cancel();
    _subscription = null;
    _entitled = false;
    isPro.value = false;
  }

  static void _publish() => isPro.value = _entitled;
}
