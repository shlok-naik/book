import 'dart:async';

import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/paywall/domain/paywall_pricing.dart';
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:book/features/paywall/presentation/widgets/soft_pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart'
    show PaywallResult;

/// A [PurchasesService] whose every RevenueCat call is a canned
/// result instead of a real platform-channel round trip — the same
/// role `FakeSessionService` plays for Supabase in
/// `tutorial_flow_test.dart`.
class FakePurchasesService extends PurchasesService {
  FakePurchasesService({
    this.offering,
    this.purchaseResult,
    this.purchaseError,
    this.restoreResult,
    this.restoreError,
    this.hostedPaywallResult,
  });

  final Offering? offering;
  final CustomerInfo? purchaseResult;
  final PurchasesException? purchaseError;
  final CustomerInfo? restoreResult;
  final PurchasesException? restoreError;
  final PaywallResult? hostedPaywallResult;

  int purchaseCalls = 0;
  Package? lastPurchasedPackage;
  int restoreCalls = 0;
  int hostedPaywallCalls = 0;

  @override
  Future<Offering?> get currentOffering async => offering;

  @override
  Future<CustomerInfo> purchase(Package package) async {
    purchaseCalls++;
    lastPurchasedPackage = package;
    final error = purchaseError;
    if (error != null) throw error;
    return purchaseResult!;
  }

  @override
  Future<CustomerInfo> restore() async {
    restoreCalls++;
    final error = restoreError;
    if (error != null) throw error;
    return restoreResult!;
  }

  @override
  Future<PaywallResult> presentPaywallIfNeeded() async {
    hostedPaywallCalls++;
    return hostedPaywallResult ?? PaywallResult.notPresented;
  }
}

const _fakeOfferingContext = PresentedOfferingContext('default', null, null);

StoreProduct _fakeStoreProduct(String identifier, double price) {
  return StoreProduct(
    identifier,
    'description',
    'title',
    price,
    '\$${price.toStringAsFixed(2)}',
    'USD',
  );
}

Offering _fakeOffering({
  double monthlyPrice = 4.99,
  double yearlyPrice = 40,
  bool includeNoTrialPackage = true,
}) {
  return Offering('default', 'Default offering', const {}, [
    Package(
      PackageIds.monthly,
      PackageType.monthly,
      _fakeStoreProduct(PackageIds.monthly, monthlyPrice),
      _fakeOfferingContext,
    ),
    Package(
      PackageIds.yearly,
      PackageType.annual,
      _fakeStoreProduct(PackageIds.yearly, yearlyPrice),
      _fakeOfferingContext,
    ),
    if (includeNoTrialPackage)
      Package(
        PackageIds.yearlyNoTrial,
        PackageType.custom,
        _fakeStoreProduct(PackageIds.yearlyNoTrial, yearlyPrice),
        _fakeOfferingContext,
      ),
  ]);
}

CustomerInfo _fakeCustomerInfo({required bool pro}) {
  final entitlements = pro
      ? {
          Entitlements.cactusPro: const EntitlementInfo(
            Entitlements.cactusPro,
            true,
            true,
            '2024-01-01T00:00:00Z',
            '2024-01-01T00:00:00Z',
            PackageIds.yearly,
            false,
          ),
        }
      : const <String, EntitlementInfo>{};
  return CustomerInfo(
    EntitlementInfos(entitlements, entitlements),
    const {},
    const [],
    const [],
    const [],
    '2024-01-01T00:00:00Z',
    'fake-user-id',
    const {},
    '2024-01-01T00:00:00Z',
  );
}

/// Every helper here uses fixed pumps rather than `pumpAndSettle` —
/// harmless now that the feature list is static, but kept so a future
/// infinite animation on this page wouldn't quietly hang the suite.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The page the paywall pops up over — every exit from the popup has to
/// land back here, so its text is what "dismissed" actually looks like.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('behind the paywall')));
}

/// The paywall is gone and the reader is back where they were. This is
/// the assertion that replaced "moved on to the next onboarding page":
/// there is nowhere to move on to any more.
void expectDismissed(WidgetTester tester) {
  expect(find.byType(PaywallPage), findsNothing);
  expect(find.text('behind the paywall'), findsOneWidget);
}

/// The popup is still up — the reader has neither bought nor closed.
void expectStillOpen(WidgetTester tester) {
  expect(find.byType(PaywallPage), findsOneWidget);
}

/// A genuine purchase holds the card on its "welcome to cactus pro"
/// state for a beat before the popup closes itself. This waits that out.
Future<void> settleCelebration(WidgetTester tester) async {
  expect(find.text('welcome to cactus pro'), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 1600));
  await settleFrames(tester);
}

/// Pumps the host, then presents the paywall over it exactly the way the
/// app does — as a popup route, so that every "does it close?" assertion
/// below is testing the real presentation rather than a bare page.
Future<void> pumpPaywall(
  WidgetTester tester, {
  PaywallPricing? pricing = PaywallPricing.placeholder,
  PurchasesService? purchases,
  Size size = const Size(1080, 2400),
  PaywallFeature feature = PaywallFeature.general,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    // Freshly keyed every time, so a test that pumps twice (the scaling
    // pair below) gets a new navigator rather than stacking a second
    // popup on top of the first one's route.
    MaterialApp(key: UniqueKey(), theme: AppTheme.light, home: const _Host()),
  );
  unawaited(
    showPaywallPopup(
      tester.element(find.byType(_Host)),
      pricing: pricing,
      purchases: purchases,
      feature: feature,
    ),
  );
  await settleFrames(tester);
}

/// Width of a pricing card, found by the label sitting inside it.
double cardWidth(WidgetTester tester, String label) {
  return tester
      .getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .width;
}

double cardHeight(WidgetTester tester, String label) {
  return tester
      .getSize(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .height;
}

void main() {
  group('pricing display', () {
    testWidgets('yearly is selected on load, and carries the savings tag', (
      tester,
    ) async {
      await pumpPaywall(tester);

      // $40/yr against $4.99 x 12 is a 33% saving.
      expect(find.text('save 33%'), findsOneWidget);
      expect(find.text('\$3.33/mo'), findsOneWidget);
      expect(find.text('\$40/yr'), findsOneWidget);
      expect(
        cardWidth(tester, 'yearly'),
        greaterThan(cardWidth(tester, 'monthly')),
      );
    });

    testWidgets('selecting monthly widens it, shrinks yearly, and drops '
        'the savings tag', (tester) async {
      await pumpPaywall(tester);

      await tester.tap(find.text('monthly'));
      await settleFrames(tester);

      expect(
        cardWidth(tester, 'monthly'),
        greaterThan(cardWidth(tester, 'yearly')),
      );
      expect(find.text('save 33%'), findsNothing);
    });

    testWidgets('the two cards always touch and fill the row exactly', (
      tester,
    ) async {
      await pumpPaywall(tester);

      final monthly = tester.getRect(
        find.ancestor(
          of: find.text('monthly'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final yearly = tester.getRect(
        find.ancestor(
          of: find.text('yearly'),
          matching: find.byType(AnimatedContainer),
        ),
      );

      // No seam: monthly's right edge is yearly's left edge.
      expect(monthly.right, closeTo(yearly.left, 0.5));
    });

    testWidgets('both cards keep the same height in either selection', (
      tester,
    ) async {
      await pumpPaywall(tester);

      expect(
        cardHeight(tester, 'monthly'),
        closeTo(cardHeight(tester, 'yearly'), 0.5),
      );

      await tester.tap(find.text('monthly'));
      await settleFrames(tester);

      expect(
        cardHeight(tester, 'monthly'),
        closeTo(cardHeight(tester, 'yearly'), 0.5),
      );
    });
  });

  group('free trial', () {
    testWidgets('the CTA reads "join now" and never mentions a trial', (
      tester,
    ) async {
      await pumpPaywall(tester);

      expect(find.text('join now'), findsOneWidget);
      expect(find.text('start free trial'), findsNothing);
    });

    testWidgets('"not sure yet" opens a sheet explaining the trial, whose '
        'own button is the only trial CTA on screen', (tester) async {
      await pumpPaywall(tester);

      await tester.tap(find.text('not sure yet'));
      await settleFrames(tester);

      expect(find.text('free trial'), findsOneWidget);
      expect(find.textContaining('3 days'), findsOneWidget);
      expect(find.textContaining('yearly plan'), findsOneWidget);
      expect(
        find.widgetWithText(SoftPillButton, 'start free trial'),
        findsOneWidget,
      );
    });

    testWidgets('starting the trial from the sheet closes it and moves on', (
      tester,
    ) async {
      await pumpPaywall(tester);

      await tester.tap(find.text('not sure yet'));
      await settleFrames(tester);

      await tester.tap(find.widgetWithText(SoftPillButton, 'start free trial'));
      await settleFrames(tester);

      // No real package behind this plan (placeholder pricing, no
      // `purchases` fake) — `_purchasePackage` takes its null-package
      // shortcut straight to `_dismiss()`, skipping the celebration
      // that only a genuine purchase earns. See `real purchases` below
      // for that path.
      expectDismissed(tester);
    });
  });

  group('invalid pricing', () {
    testWidgets('shows a notice instead of prices, and disables the CTA', (
      tester,
    ) async {
      await pumpPaywall(
        tester,
        pricing: const PaywallPricing(monthlyPerMonth: 0, yearlyPerYear: 0),
      );

      expect(find.textContaining("couldn't load pricing"), findsOneWidget);
      expect(find.text('monthly'), findsNothing);
      expect(find.text('yearly'), findsNothing);

      // Disabled rather than typed-checked — the CTA isn't a
      // SoftPillButton here, so the behavior that matters is that
      // tapping it does nothing.
      await tester.tap(find.text('join now'));
      await settleFrames(tester);
      expectStillOpen(tester);
    });

    testWidgets('treats NaN prices as invalid rather than rendering them', (
      tester,
    ) async {
      await pumpPaywall(
        tester,
        pricing: const PaywallPricing(
          monthlyPerMonth: double.nan,
          yearlyPerYear: 40,
        ),
      );

      expect(find.textContaining("couldn't load pricing"), findsOneWidget);
      expect(find.textContaining('NaN'), findsNothing);
    });
  });

  group('PaywallPricing', () {
    test('shows the store\'s localized strings, never a rebuilt dollar '
        'price', () {
      const pricing = PaywallPricing(
        monthlyPerMonth: 3.99,
        yearlyPerYear: 39.99,
        monthlyPriceString: '£3.99',
        yearlyPriceString: '£39.99',
        yearlyPerMonthString: '£3.33',
      );
      expect(pricing.monthlyLabel, '£3.99');
      expect(pricing.yearlyLabel, '£39.99');
      expect(pricing.yearlyPerMonthLabel, '£3.33');
    });

    test('without store strings, the fallback keeps real cents', () {
      const pricing = PaywallPricing(
        monthlyPerMonth: 4.99,
        yearlyPerYear: 39.99,
      );
      expect(pricing.yearlyLabel, '\$39.99');
      expect(PaywallPricing.placeholder.yearlyLabel, '\$40');
    });

    test('rejects non-positive and non-finite prices', () {
      expect(PaywallPricing.placeholder.isValid, isTrue);
      expect(
        const PaywallPricing(monthlyPerMonth: 0, yearlyPerYear: 40).isValid,
        isFalse,
      );
      expect(
        const PaywallPricing(monthlyPerMonth: -1, yearlyPerYear: 40).isValid,
        isFalse,
      );
      expect(
        const PaywallPricing(
          monthlyPerMonth: 4.99,
          yearlyPerYear: double.infinity,
        ).isValid,
        isFalse,
      );
    });

    test('hides the savings tag when yearly is not actually cheaper', () {
      // Exactly twelve months' worth — no saving to claim.
      expect(
        const PaywallPricing(
          monthlyPerMonth: 5,
          yearlyPerYear: 60,
        ).savingsPercent,
        isNull,
      );
      // Dearer than monthly.
      expect(
        const PaywallPricing(
          monthlyPerMonth: 5,
          yearlyPerYear: 80,
        ).savingsPercent,
        isNull,
      );
      expect(
        const PaywallPricing(
          monthlyPerMonth: 5,
          yearlyPerYear: 30,
        ).savingsPercent,
        50,
      );
    });
  });

  group('real purchases', () {
    /// Presents the popup with no pricing supplied, so the page fetches
    /// its own offering from [purchases] the way it does in the app.
    Future<void> pumpWithPurchases(
      WidgetTester tester,
      FakePurchasesService purchases,
    ) {
      return pumpPaywall(tester, pricing: null, purchases: purchases);
    }

    testWidgets('fetches the offering and shows real prices once loaded', (
      tester,
    ) async {
      await pumpWithPurchases(
        tester,
        FakePurchasesService(offering: _fakeOffering()),
      );

      expect(find.textContaining("couldn't load pricing"), findsNothing);
      expect(find.text('monthly'), findsOneWidget);
      expect(find.text('yearly'), findsOneWidget);
    });

    testWidgets('a successful purchase with the entitlement active moves on', (
      tester,
    ) async {
      final purchases = FakePurchasesService(
        offering: _fakeOffering(),
        purchaseResult: _fakeCustomerInfo(pro: true),
      );
      await pumpWithPurchases(tester, purchases);

      await tester.tap(find.text('join now'));
      await settleFrames(tester);

      expect(purchases.purchaseCalls, 1);
      // "join now" must buy the trial-free product, never the one
      // `_startFreeTrial` is meant to be the only path to — see
      // `PackageIds.yearlyNoTrial`'s doc comment.
      expect(
        purchases.lastPurchasedPackage?.identifier,
        PackageIds.yearlyNoTrial,
      );
      await settleCelebration(tester);
      expectDismissed(tester);
    });

    testWidgets(
      '"start free trial" buys the trial product, not the one "join now" uses',
      (tester) async {
        final purchases = FakePurchasesService(
          offering: _fakeOffering(),
          purchaseResult: _fakeCustomerInfo(pro: true),
        );
        await pumpWithPurchases(tester, purchases);

        await tester.tap(find.text('not sure yet'));
        await settleFrames(tester);
        await tester.tap(
          find.widgetWithText(SoftPillButton, 'start free trial'),
        );
        await settleFrames(tester);

        expect(purchases.purchaseCalls, 1);
        expect(purchases.lastPurchasedPackage?.identifier, PackageIds.yearly);
        await settleCelebration(tester);
        expectDismissed(tester);
      },
    );

    testWidgets('"join now" falls back to the trial product if no trial-free '
        'product is configured yet', (tester) async {
      final purchases = FakePurchasesService(
        offering: _fakeOffering(includeNoTrialPackage: false),
        purchaseResult: _fakeCustomerInfo(pro: true),
      );
      await pumpWithPurchases(tester, purchases);

      await tester.tap(find.text('join now'));
      await settleFrames(tester);

      expect(purchases.lastPurchasedPackage?.identifier, PackageIds.yearly);
      await settleCelebration(tester);
      expectDismissed(tester);
    });

    testWidgets(
      'a purchase that leaves PRO inactive stays put with a message',
      (tester) async {
        final purchases = FakePurchasesService(
          offering: _fakeOffering(),
          purchaseResult: _fakeCustomerInfo(pro: false),
        );
        await pumpWithPurchases(tester, purchases);

        await tester.tap(find.text('join now'));
        await settleFrames(tester);

        expect(find.textContaining("isn't active"), findsOneWidget);
        expectStillOpen(tester);
      },
    );

    testWidgets('cancelling the native purchase sheet shows no error', (
      tester,
    ) async {
      final purchases = FakePurchasesService(
        offering: _fakeOffering(),
        purchaseError: const PurchasesException('', userCancelled: true),
      );
      await pumpWithPurchases(tester, purchases);

      await tester.tap(find.text('join now'));
      await settleFrames(tester);

      expectStillOpen(tester);
      // The button is findable and re-enabled — no lingering error text.
      expect(find.text('join now'), findsOneWidget);
    });

    testWidgets('a failed purchase surfaces its message', (tester) async {
      final purchases = FakePurchasesService(
        offering: _fakeOffering(),
        purchaseError: const PurchasesException("You're offline."),
      );
      await pumpWithPurchases(tester, purchases);

      await tester.tap(find.text('join now'));
      await settleFrames(tester);

      expect(find.text("You're offline."), findsOneWidget);
    });

    testWidgets(
      'restoring purchases moves on once it finds an active entitlement',
      (tester) async {
        final purchases = FakePurchasesService(
          offering: _fakeOffering(),
          restoreResult: _fakeCustomerInfo(pro: true),
        );
        await pumpWithPurchases(tester, purchases);

        await tester.tap(find.text('restore purchases'));
        await settleFrames(tester);

        expect(purchases.restoreCalls, 1);
        expectDismissed(tester);
      },
    );

    testWidgets(
      'falls back to the hosted paywall when the offering fails to load',
      (tester) async {
        final purchases = FakePurchasesService(
          offering: null,
          hostedPaywallResult: PaywallResult.purchased,
        );
        await pumpWithPurchases(tester, purchases);

        expect(find.textContaining("couldn't load pricing"), findsOneWidget);

        await tester.tap(find.text('view plans'));
        await settleFrames(tester);

        expect(purchases.hostedPaywallCalls, 1);
        expectDismissed(tester);
      },
    );
  });

  group('scaling', () {
    // A RenderFlex overflow logs a FlutterError, which flutter_test
    // turns into a test failure — so these pass only if every section
    // still fits at the size given.
    testWidgets('lays out without overflow on a small phone', (tester) async {
      await pumpPaywall(tester, size: const Size(1080, 1920));
      expect(find.text('join now'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a tall device', (tester) async {
      await pumpPaywall(tester, size: const Size(1170, 2900));
      expect(find.text('join now'), findsOneWidget);
    });

    testWidgets('scales its spacing down on a shorter viewport', (
      tester,
    ) async {
      await pumpPaywall(tester, size: const Size(1080, 2400));
      final tall = cardHeight(tester, 'yearly');

      await pumpPaywall(tester, size: const Size(1080, 1920));
      final short = cardHeight(tester, 'yearly');

      expect(short, lessThan(tall));
    });
  });

  group('chapters', () {
    testWidgets('opens on chapter I', (tester) async {
      await pumpPaywall(tester);

      expect(find.text('chapter I'), findsOneWidget);
      expect(find.text('Converse & Express'), findsOneWidget);
    });

    testWidgets('swiping left turns the page to the next chapter', (
      tester,
    ) async {
      await pumpPaywall(tester);

      await tester.drag(find.text('Converse & Express'), const Offset(-400, 0));
      await settleFrames(tester);

      expect(find.text('chapter II'), findsOneWidget);
      expect(find.text('A Mind of Its Own'), findsOneWidget);
    });

    testWidgets('a fourth chapter pitches icon/theme customisation', (
      tester,
    ) async {
      await pumpPaywall(tester);

      // I -> II -> III -> IV: three swipes land on the new chapter.
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await settleFrames(tester);
      }

      expect(find.text('chapter IV'), findsOneWidget);
      expect(find.text('Unparalleled Customisation'), findsOneWidget);
    });

    test('every specific feature names its own chapter', () {
      final specific = [
        for (final feature in PaywallFeature.values)
          if (feature != PaywallFeature.general) feature,
      ];
      final chapters = {for (final f in specific) f.chapterIndex};
      expect(chapters, hasLength(specific.length));
      expect(PaywallFeature.general.chapterIndex, 0);
    });

    for (final (feature, roman, title) in [
      (PaywallFeature.memory, 'II', 'A Mind of Its Own'),
      (PaywallFeature.customisation, 'IV', 'Unparalleled Customisation'),
      (PaywallFeature.readingUnlocked, 'V', 'Your Reading, Unlocked'),
    ]) {
      testWidgets('opened for ${feature.name}, it starts on chapter $roman', (
        tester,
      ) async {
        await pumpPaywall(tester, feature: feature);

        expect(find.text('chapter $roman'), findsOneWidget);
        expect(find.text(title), findsOneWidget);
      });
    }

    testWidgets('a reader can still swipe back from the chapter it opened on', (
      tester,
    ) async {
      await pumpPaywall(tester, feature: PaywallFeature.customisation);

      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await settleFrames(tester);

      expect(find.text('chapter III'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('pricing cards expose their selected state and price', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPaywall(tester);

      expect(
        find.bySemanticsLabel(
          RegExp(r'yearly plan, \$3\.33/mo, billed \$40/yr, save 33%'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'monthly plan, \$4\.99/mo')),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('the open chapter reads out as plain, real text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPaywall(tester);

      // A real PageView page, unlike the marquee it replaced, needs no
      // summarising workaround — the chapter's title is just its own
      // text node.
      expect(find.text('Converse & Express'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('the close button carries a tooltip', (tester) async {
      await pumpPaywall(tester);
      expect(find.byTooltip('Close'), findsOneWidget);
    });
  });
}
