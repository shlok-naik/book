import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/dotted_background.dart';
import 'onboarding_progress_dots.dart';

/// The onboarding flow's shared page shape: whatever illustrates the
/// page sits centered in the top half of a plain background, and a
/// rounded-top card fills exactly the bottom half with [cardChild].
///
/// Every onboarding screen past the welcome page is built on this one
/// widget, so they can't visually drift apart from each other.
class HalfSheetScaffold extends StatelessWidget {
  const HalfSheetScaffold({
    super.key,
    this.topContent,
    required this.cardChild,
    this.showBackButton = false,
    this.progressStep,
    this.bypass,
  });

  /// What illustrates this page — centered in the top half. Null when a
  /// page has nothing to show there (most of the flow, past the
  /// tutorial page's command wall).
  final Widget? topContent;

  /// The card's contents. Wrapped in a scroll view internally, so it's
  /// safe to put more than fits at once without an overflow.
  final Widget cardChild;

  /// Pushed pages generally want a way back; only the welcome screen
  /// itself doesn't offer one.
  final bool showBackButton;

  /// Which step (1-5) of the tutorial → Q1 → account → Q2 → finish
  /// sequence this page is — shown as a fixed footer row pinned to the
  /// bottom of the card, below its scrollable content. Null hides it —
  /// used for the welcome screen and, deliberately, the tutorial pages
  /// themselves (the sequence isn't shown until Q1).
  final int? progressStep;

  /// Forwarded to [OnboardingProgressDots] — a shortcut line drawn from
  /// step `from` to step `to`, alongside (not instead of) the ordinary
  /// line through every dot. See the sign-in shortcut, which shows
  /// account (step 3) leading straight to finish.
  final ({int from, int to})? bypass;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: DottedBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = constraints.maxHeight * 0.5;

            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: cardHeight,
                  // Without its own SafeArea, `Center` would center within
                  // a region that starts at y=0 of the physical screen —
                  // including the area a status bar/notch sits over — so
                  // "centered" could still land content up against it.
                  child: SafeArea(
                    bottom: false,
                    child: Center(child: topContent ?? const SizedBox.shrink()),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: cardHeight,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.lg),
                    ),
                    child: ColoredBox(
                      color: colors.surface,
                      child: SafeArea(
                        top: false,
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(AppSpacing.xl),
                                child: cardChild,
                              ),
                            ),
                            if (progressStep != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.xl,
                                  0,
                                  AppSpacing.xl,
                                  AppSpacing.md,
                                ),
                                child: OnboardingProgressDots(
                                  currentStep: progressStep!,
                                  bypass: bypass,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (showBackButton)
                  // Explicitly Positioned rather than left as a bare Stack
                  // child: an unpositioned child is sized with *loosened*
                  // constraints from the whole Stack (i.e. up to the full
                  // screen), and despite being drawn small, the space
                  // Stack reserves for it at that alignment absorbed hit
                  // tests for the entire area below it — including the
                  // card's own button, confirmed by removing this
                  // temporarily and watching the tap start landing
                  // correctly. Positioned pins it to a small, exact box
                  // instead.
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: colors.primaryText),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
