import 'package:book/core/theme/app_colors.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/onboarding/presentation/widgets/onboarding_progress_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Four steps now — tutorial, look, goal, finish. The two account steps and
/// the bypass loop that used to hop around them went with the sign-up
/// flow: onboarding no longer creates an account, so there is no longer
/// a branch for the line to draw.

Future<List<BoxDecoration>> pumpDots(
  WidgetTester tester,
  int currentStep,
  void Function(AppColors) captureColors,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) {
          captureColors(context.colors);
          return Scaffold(
            body: OnboardingProgressDots(currentStep: currentStep),
          );
        },
      ),
    ),
  );

  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .toList();
}

void main() {
  testWidgets('fills dots up to currentStep and leaves the rest hollow', (
    tester,
  ) async {
    late AppColors colors;
    final decorations = await pumpDots(tester, 2, (c) => colors = c);

    expect(decorations, hasLength(OnboardingProgressDots.stepCount));
    expect(decorations.where((d) => d.color == colors.accent).length, 2);
    expect(
      decorations.where((d) => d.color == colors.divider).length,
      OnboardingProgressDots.stepCount - 2,
    );
  });

  testWidgets('fills every dot on the last step', (tester) async {
    late AppColors colors;
    final decorations = await pumpDots(
      tester,
      OnboardingProgressDots.stepCount,
      (c) => colors = c,
    );

    expect(
      decorations.where((d) => d.color == colors.accent).length,
      OnboardingProgressDots.stepCount,
    );
    expect(decorations.where((d) => d.color == colors.divider), isEmpty);
  });

  testWidgets('paints its connector without throwing', (tester) async {
    await pumpDots(tester, 1, (_) {});

    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
