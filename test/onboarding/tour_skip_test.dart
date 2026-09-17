import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/presentation/pages/buttons_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/goodreads_prompt_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the tour says how far along it is and can be skipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ButtonsTutorialPage()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1 of 4'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('tour-skip')));
    await tester.tap(find.byKey(const ValueKey('tour-skip')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(GoodreadsPromptPage), findsOneWidget);
  });
}
