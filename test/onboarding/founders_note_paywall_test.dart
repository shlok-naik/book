import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/presentation/pages/finish_page.dart';
import 'package:book/features/onboarding/presentation/pages/founders_note_page.dart';
import 'package:book/features/paywall/data/intro_offer_store.dart';
import 'package:book/features/paywall/domain/paywall_pricing.dart';
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../paywall/paywall_page_test.dart' show FakePurchasesService;

/// The one-time PRO paywall as it now appears at the natural end of the
/// onboarding tour — "continue" on the founder's note — rather than as
/// a popup sprung on the reader's first visit to the app. It has to
/// keep the same "shown once, whatever the reader does with it"
/// contract `RootShell`'s own intro-offer popup follows.

class _FakeIntroOfferStore extends IntroOfferStore {
  int markSeenCalls = 0;

  @override
  Future<bool> hasSeen() async => false;

  @override
  Future<void> markSeen() async => markSeenCalls++;
}

const _pricing = PaywallPricing.placeholder;

Future<void> pumpFoundersNote(
  WidgetTester tester, {
  required IntroOfferStore introOffer,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: FoundersNotePage(
        purchases: FakePurchasesService(),
        pricing: _pricing,
        introOffer: introOffer,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('continue marks the intro offer seen and opens the paywall', (
    tester,
  ) async {
    final store = _FakeIntroOfferStore();
    await pumpFoundersNote(tester, introOffer: store);

    await tester.tap(find.text('continue'));
    await tester.pumpAndSettle();

    // Marked before the popup is even shown — a reader who force-quits
    // while looking at it still shouldn't be met with it again, the
    // same rule `RootShell._maybeShowIntroOffer` follows.
    expect(store.markSeenCalls, 1);
    expect(find.byType(PaywallPage), findsOneWidget);
    expect(find.byType(FinishPage), findsNothing);
  });

  testWidgets('closing the paywall still hands over to the finish screen', (
    tester,
  ) async {
    await pumpFoundersNote(tester, introOffer: _FakeIntroOfferStore());

    await tester.tap(find.text('continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // The paywall is a pitch here too, not a gate — closing it (rather
    // than buying) still moves the reader on to the last onboarding
    // screen.
    expect(find.byType(PaywallPage), findsNothing);
    expect(find.byType(FinishPage), findsOneWidget);
  });
}
