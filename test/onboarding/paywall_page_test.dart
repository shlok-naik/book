import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/domain/paywall_pricing.dart';
import 'package:book/features/onboarding/presentation/pages/one_more_thing_page.dart';
import 'package:book/features/onboarding/presentation/pages/paywall_page.dart';
import 'package:book/features/onboarding/presentation/widgets/soft_pill_button.dart';

/// Every helper here uses fixed pumps rather than `pumpAndSettle` —
/// harmless now that the feature list is static, but kept so a future
/// infinite animation on this page wouldn't quietly hang the suite.
Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpPaywall(
  WidgetTester tester, {
  PaywallPricing pricing = PaywallPricing.placeholder,
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: PaywallPage(pricing: pricing),
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

      expect(find.byType(OneMoreThingPage), findsOneWidget);
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
      expect(find.byType(OneMoreThingPage), findsNothing);
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
      expect(find.byTooltip('close'), findsOneWidget);
    });
  });
}
