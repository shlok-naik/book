import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:book/core/theme/app_colors.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/presentation/widgets/onboarding_progress_dots.dart';

void main() {
  testWidgets('fills dots up to currentStep and leaves the rest hollow', (
    tester,
  ) async {
    late AppColors colors;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            colors = context.colors;
            return const Scaffold(body: OnboardingProgressDots(currentStep: 3));
          },
        ),
      ),
    );

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .toList();

    expect(decorations, hasLength(OnboardingProgressDots.stepCount));
    final filled = decorations.where((d) => d.color == colors.accent).length;
    final hollow = decorations.where((d) => d.color == colors.divider).length;
    expect(filled, 3);
    expect(hollow, 2);
  });

  testWidgets('renders a bypass line without throwing, and leaves the dots it '
      'skips over hollow even past currentStep', (tester) async {
    late AppColors colors;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            colors = context.colors;
            return const Scaffold(
              body: OnboardingProgressDots(
                currentStep: 5,
                bypass: (from: 2, to: 5),
              ),
            );
          },
        ),
      ),
    );

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .toList();

    // Dots 3 and 4 sit strictly inside the (from: 2, to: 5) bypass —
    // never actually reached on this path — so they stay hollow even
    // though currentStep is 5; only dots 1, 2, and 5 fill in.
    expect(decorations, hasLength(OnboardingProgressDots.stepCount));
    expect(decorations.where((d) => d.color == colors.accent).length, 3);
    expect(decorations.where((d) => d.color == colors.divider).length, 2);

    // The connector painter is present and didn't throw during paint.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
