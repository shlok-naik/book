import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/presentation/pages/tutorial_step_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the top content, heading, description, and button', (
    tester,
  ) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TutorialStepPage(
          topContent: const Text('mock content'),
          heading: 'a heading',
          description: const Text('a description'),
          onContinue: () => continued = true,
        ),
      ),
    );

    expect(find.text('mock content'), findsOneWidget);
    expect(find.text('a heading'), findsOneWidget);
    expect(find.text('a description'), findsOneWidget);
    expect(find.text('continue'), findsOneWidget);

    await tester.tap(find.text('continue'));
    expect(continued, isTrue);
  });

  testWidgets('uses a custom button label when given one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TutorialStepPage(
          topContent: const SizedBox.shrink(),
          heading: 'heading',
          description: const Text('description'),
          buttonLabel: 'Next',
          onContinue: () {},
        ),
      ),
    );

    expect(find.text('Next'), findsOneWidget);
    expect(find.text('continue'), findsNothing);
  });

  testWidgets('the card fills exactly the bottom half of the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TutorialStepPage(
          topContent: const SizedBox.shrink(),
          heading: 'heading',
          description: const Text('description'),
          onContinue: () {},
        ),
      ),
    );

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final card = tester.widget<ClipRRect>(find.byType(ClipRRect));
    final cardRect = tester.getRect(find.byWidget(card));

    expect(cardRect.height, closeTo(screenHeight * 0.5, 0.5));
  });
}
