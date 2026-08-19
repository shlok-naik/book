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

  testWidgets(
    'renders a bypass line without throwing, and dot fill still follows '
    'currentStep alone',
    (tester) async {
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

      // All 5 dots still fill up to currentStep — a bypass only adds a
      // second line, it doesn't change which dots light up.
      expect(decorations, hasLength(OnboardingProgressDots.stepCount));
      expect(
        decorations.where((d) => d.color == colors.accent).length,
        OnboardingProgressDots.stepCount,
      );

      // The connector painter is present and didn't throw during paint.
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
