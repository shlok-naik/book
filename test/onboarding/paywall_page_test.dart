import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/domain/paywall_pricing.dart';
import 'package:book/features/onboarding/presentation/pages/paywall_page.dart';
import 'package:book/features/onboarding/presentation/widgets/soft_pill_button.dart';

/// The paywall's feature wall marquees forever, so `pumpAndSettle`
/// would never return — every helper here uses fixed pumps instead.
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
    testWidgets('is off by default, and the CTA reads "join now"', (
      tester,
    ) async {
      await pumpPaywall(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.widgetWithText(SoftPillButton, 'join now'), findsOneWidget);
    });

    testWidgets('turning it on switches the CTA to the trial wording', (
      tester,
    ) async {
      await pumpPaywall(tester);

      await tester.tap(find.byType(Switch));
      await settleFrames(tester);

      expect(
        find.widgetWithText(SoftPillButton, 'start free trial'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SoftPillButton, 'join now'), findsNothing);
    });

    testWidgets('turning it on from monthly moves the reader to yearly — '
        'trials are a yearly perk', (tester) async {
      await pumpPaywall(tester);

      await tester.tap(find.text('monthly'));
      await settleFrames(tester);
      expect(
        cardWidth(tester, 'monthly'),
        greaterThan(cardWidth(tester, 'yearly')),
      );

      await tester.tap(find.byType(Switch));
      await settleFrames(tester);

      expect(
        cardWidth(tester, 'yearly'),
        greaterThan(cardWidth(tester, 'monthly')),
      );
    });

    testWidgets('picking monthly switches an active trial back off', (
      tester,
    ) async {
      await pumpPaywall(tester);

      await tester.tap(find.byType(Switch));
      await settleFrames(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.text('monthly'));
      await settleFrames(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.widgetWithText(SoftPillButton, 'join now'), findsOneWidget);
    });
  });

  group('invalid pricing', () {
    testWidgets('shows a notice instead of prices, and disables the CTA '
        'and the trial toggle', (tester) async {
      await pumpPaywall(
        tester,
        pricing: const PaywallPricing(monthlyPerMonth: 0, yearlyPerYear: 0),
      );

      expect(find.textContaining("couldn't load pricing"), findsOneWidget);
      expect(find.text('monthly'), findsNothing);
      expect(find.text('yearly'), findsNothing);

      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        tester
            .widget<SoftPillButton>(
              find.widgetWithText(SoftPillButton, 'join now'),
            )
            .onPressed,
        isNull,
      );
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
      expect(find.widgetWithText(SoftPillButton, 'join now'), findsOneWidget);
    });

    testWidgets('lays out without overflow on a tall device', (tester) async {
      await pumpPaywall(tester, size: const Size(1170, 2900));
      expect(find.widgetWithText(SoftPillButton, 'join now'), findsOneWidget);
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

    testWidgets('the marquee is summarised once rather than read out per '
        'repeat', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPaywall(tester);

      // The wall repeats each pill several times to fake the loop; the
      // semantics tree should carry exactly one summary instead.
      expect(
        find.bySemanticsLabel(RegExp('included with cactus PRO:.*')),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('the close button carries a tooltip', (tester) async {
      await pumpPaywall(tester);
      expect(find.byTooltip('close'), findsOneWidget);
    });
  });
}
