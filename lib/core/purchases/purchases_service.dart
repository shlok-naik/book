import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../env/env.dart';
import 'entitlements.dart';

/// A failure from any [PurchasesService] call, already written for a
/// human — the UI shows [message] verbatim. The original error is kept
/// in [cause] for logging only, never rendered. Mirrors
/// `OnboardingException`'s shape.
class PurchasesException implements Exception {
  const PurchasesException(
    this.message, {
    this.cause,
    this.userCancelled = false,
  });

  final String message;
  final Object? cause;

  /// True when the "failure" was just the reader backing out of the
  /// native purchase sheet — never worth surfacing as an error banner,
  /// only worth quietly re-enabling the CTA.
  final bool userCancelled;

  @override
  String toString() =>
      'PurchasesException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Thin wrapper over the RevenueCat `Purchases`/`RevenueCatUI` SDKs —
/// configuration, offerings, purchasing, restoring, and entitlement
/// checks for [Entitlements.cactusPro].
///
/// [configure] runs once at startup (see `main.dart`, mirroring
/// `SupabaseService.init`). Everywhere else, a `PurchasesService` is a
/// stateless wrapper around the SDK's own global instance — the same
/// relationship `SessionService` has with `Supabase.instance.client` —
/// so it's safe to construct one wherever it's needed rather than
/// threading a single instance through every page in between.
///
/// Every method translates a RevenueCat [PlatformException] into a
/// [PurchasesException] with a message safe to show directly, the same
/// way `SessionService` translates Supabase/network failures.
class PurchasesService {
  const PurchasesService();

  /// Configures the RevenueCat SDK. Call exactly once, before any other
  /// `Purchases`/`RevenueCatUI`/[PurchasesService] use — see `main.dart`.
  static Future<void> configure() {
    return Purchases.configure(PurchasesConfiguration(Env.revenueCatApiKey));
  }

  static StreamController<CustomerInfo>? _customerInfoController;

  /// Live updates whenever purchases, restores, or renewals change the
  /// reader's entitlements — from any device, since RevenueCat pushes
  /// these from its own servers rather than only after a local call.
  /// Backed by a single shared listener (the underlying SDK callback
  /// API isn't itself a stream), lazily attached on first listen and
  /// detached once nothing is listening.
  static Stream<CustomerInfo> get customerInfoStream {
    final existing = _customerInfoController;
    if (existing != null) return existing.stream;

    // The controller's lifetime is its listeners': `onCancel` below both
    // detaches the SDK callback and drops the static reference, so
    // nothing is left holding it open. The analyzer cannot see that
    // through the static field, hence the ignore.
    // ignore: close_sinks
    late final StreamController<CustomerInfo> controller;
    void listener(CustomerInfo info) => controller.add(info);

    controller = StreamController<CustomerInfo>.broadcast(
      onCancel: () {
        Purchases.removeCustomerInfoUpdateListener(listener);
        _customerInfoController = null;
      },
    );
    Purchases.addCustomerInfoUpdateListener(listener);
    _customerInfoController = controller;
    return controller.stream;
  }

  /// Links the RevenueCat-tracked purchaser to the reader's own app
  /// account id, so entitlements follow them across devices and
  /// reinstalls rather than staying pinned to this device's anonymous
  /// id. Call right after a sign-in/sign-up succeeds.
  Future<void> identify(String appUserId) {
    return _run(() => Purchases.logIn(appUserId));
  }

  /// Reverts to a fresh, anonymous, device-scoped id — call on
  /// sign-out so the next reader on this device doesn't inherit the
  /// previous one's entitlements.
  Future<void> reset() => _run(() => Purchases.logOut());

  Future<CustomerInfo> get customerInfo => _run(Purchases.getCustomerInfo);

  /// Whether the given [info] carries the active [Entitlements.cactusPro]
  /// entitlement — the one check every premium gate in the app should
  /// go through, rather than each caller re-deriving it from the raw
  /// entitlement map.
  bool isPro(CustomerInfo info) =>
      info.entitlements.active.containsKey(Entitlements.cactusPro);

  /// The offering to show on the paywall — `Offerings.current`, whichever
  /// one is marked "current" in the RevenueCat dashboard, so switching
  /// offerings (an A/B test, a promo) never needs an app update. Null
  /// when nothing is configured yet (or the fetch fails and the caller
  /// chooses to swallow the resulting [PurchasesException]).
  Future<Offering?> get currentOffering async {
    final offerings = await _run(Purchases.getOfferings);
    return offerings.current;
  }

  /// Buys [package], returning the fresh [CustomerInfo] once the store
  /// and RevenueCat have both confirmed it. Check [isPro] against the
  /// result rather than assuming success implies entitlement — a
  /// purchase can succeed for a product that isn't actually mapped to
  /// [Entitlements.cactusPro] if the dashboard is misconfigured.
  ///
  /// Goes through `Purchases.purchase` with a [PurchaseParams] — the
  /// SDK's current unified purchase entry point — rather than the
  /// older, now-deprecated `purchasePackage` shortcut.
  Future<CustomerInfo> purchase(Package package) async {
    final result = await _run(
      () => Purchases.purchase(PurchaseParams.package(package)),
    );
    return result.customerInfo;
  }

  /// Re-links past purchases to this install — the flow App Store/Play
  /// review requires be reachable without signing in again, for a
  /// reader who reinstalled or switched devices.
  Future<CustomerInfo> restore() => _run(Purchases.restorePurchases);

  /// Presents RevenueCat's own dashboard-configured paywall — the
  /// managed fallback for when the app's bespoke `PaywallPage` can't
  /// load its own offering, or a quick way to gate any other premium
  /// screen without building a custom UI for it. Already checks
  /// [Entitlements.cactusPro] itself, so it's a no-op (returns
  /// [PaywallResult.notPresented]) for a reader who's already PRO.
  Future<PaywallResult> presentPaywallIfNeeded() {
    return RevenueCatUI.presentPaywallIfNeeded(Entitlements.cactusPro);
  }

  /// Presents RevenueCat's Customer Center — self-serve manage/cancel/
  /// refund-request flows with no custom UI to build or maintain. See
  /// `ProfilePage`, the app's one natural "account settings" spot.
  Future<void> presentCustomerCenter() {
    return RevenueCatUI.presentCustomerCenter();
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        throw const PurchasesException('', userCancelled: true);
      }
      throw PurchasesException(_messageFor(code), cause: error);
    }
  }

  String _messageFor(PurchasesErrorCode code) {
    switch (code) {
      case PurchasesErrorCode.networkError:
      case PurchasesErrorCode.offlineConnectionError:
        return "You're offline — connect to the internet and try again.";
      case PurchasesErrorCode.purchaseNotAllowedError:
        return "Purchases aren't allowed on this device.";
      case PurchasesErrorCode.productAlreadyPurchasedError:
        return 'You already own this.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Your payment is pending approval — check back shortly.';
      case PurchasesErrorCode.receiptAlreadyInUseError:
        return 'That purchase is already linked to another account.';
      case PurchasesErrorCode.invalidCredentialsError:
      case PurchasesErrorCode.configurationError:
        return "We couldn't reach the store right now. Try again in a moment.";
      default:
        return 'Something went wrong. Try again in a moment.';
    }
  }
}
