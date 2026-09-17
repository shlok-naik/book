import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../first_steps_controller.dart';

/// The add tab's "first steps" checklist — Fable's "let's get set up" card,
/// for a reader who'd rather be shown the next tap than read a tour. Each
/// row does its step in one tap ([onStep]); a done step is ticked and can't
/// be tapped. Plain rows and a hairline, no card chrome, like the rest of
/// the add tab.
///
/// Deliberately compact, and only ever the steps still to do: it sits above
/// the book being read on a page whose main event is the command line, so a
/// ticked row the reader can no longer act on would only take space from it.
class FirstStepsCard extends StatelessWidget {
  const FirstStepsCard({
    super.key,
    required this.done,
    required this.onStep,
    required this.onDismiss,
  });

  final Set<FirstStep> done;

  /// Called for a step that isn't done yet. Null for a step that can't be
  /// started from here right now (logging a page with no book).
  final VoidCallback? Function(FirstStep step) onStep;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fonts = context.fonts;

    return Column(
      key: const ValueKey('first-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'first steps · ${done.length} of ${FirstStep.values.length}',
                  style: fonts.interface(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('first-steps-dismiss'),
              tooltip: 'Hide first steps',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              onPressed: () {
                AppHaptics.selection();
                onDismiss();
              },
              icon: Icon(Icons.close, size: 20, color: colors.secondaryText),
            ),
          ],
        ),
        // Only what is left: a ticked row the reader can't act on is just
        // height taken from the command line underneath.
        for (final step in FirstStep.values)
          if (!done.contains(step)) _StepRow(step: step, onTap: onStep(step)),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, this.onTap});

  final FirstStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tap = onTap;
    return Semantics(
      button: tap != null,
      checked: false,
      label: step.label,
      excludeSemantics: true,
      onTap: tap,
      child: InkWell(
        key: ValueKey('first-step-${step.name}'),
        onTap: tap == null
            ? null
            : () {
                AppHaptics.selection();
                tap();
              },
        child: ConstrainedBox(
          // Still a comfortable target, but shorter than a settings row:
          // the checklist shares this page with the command line.
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(
                Icons.radio_button_unchecked,
                size: 16,
                color: colors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  step.label,
                  style: context.fonts.body(
                    fontSize: 14,
                    color: colors.primaryText,
                  ),
                ),
              ),
              if (tap != null)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: colors.secondaryText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
