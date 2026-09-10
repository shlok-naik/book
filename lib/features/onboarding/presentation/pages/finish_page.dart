import 'package:flutter/material.dart';

import '../../../../core/analytics/app_analytics.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../shell/presentation/pages/root_shell.dart';
import '../../data/onboarding_store.dart';
import '../widgets/celebration_page.dart';

/// The last screen before the app itself.
///
/// This is where the intro is marked as done — not the first screen —
/// so a reader who quits halfway through gets it again rather than
/// losing it to a launch they never finished. It replaces the whole
/// navigation stack with [RootShell] rather than pushing, so none of the
/// intro can be popped back to.
class FinishPage extends StatelessWidget {
  const FinishPage({super.key, this.store});

  /// Injection point for tests: a fake flag store, so a test can watch
  /// the intro being marked done without touching device storage.
  final OnboardingStore? store;

  @override
  Widget build(BuildContext context) {
    return CelebrationPage(
      icon: Icon(Icons.check_circle, size: 72, color: context.colors.accent),
      title: 'All Set!',
      message:
          "welcome to cactus - you're all set. you can start adding to "
          'your library or import it from elsewhere and, most '
          'importantly: start reading.',
      buttonLabel: "let's go",
      onContinue: () {
        // The funnel's denominator: everything above this is a step
        // someone might not have taken.
        AppAnalytics.onboardingCompleted();
        // Fire-and-forget, and deliberately not awaited before
        // navigating: the reader tapped "let's go" and should get the
        // app now. A write that loses the race only costs them the intro
        // once more, which is why `reportingFailure` records it rather
        // than dropping it.
        reportingFailure(
          (store ?? const OnboardingStore()).markSeen(),
          source: 'FinishPage',
          message: 'Could not record that onboarding finished.',
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'root_shell'),
            builder: (_) => const RootShell(),
          ),
          (route) => false,
        );
      },
    );
  }
}
