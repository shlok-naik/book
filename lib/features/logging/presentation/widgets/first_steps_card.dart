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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('first-steps-dismiss'),
              tooltip: 'Hide first steps',
              onPressed: () {
                AppHaptics.selection();
                onDismiss();
              },
              icon: Icon(Icons.close, size: 20, color: colors.secondaryText),
            ),
          ],
        ),
        for (final step in FirstStep.values)
          _StepRow(step: step, done: done.contains(step), onTap: onStep(step)),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.done, this.onTap});

  final FirstStep step;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tap = done ? null : onTap;
    return Semantics(
      button: tap != null,
      checked: done,
      label: step.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('first-step-${step.name}'),
        onTap: tap == null
            ? null
            : () {
                AppHaptics.selection();
                tap();
              },
        child: ConstrainedBox(
          // Comfortably over the 44pt minimum: this row is for readers who
          // are least sure where to tap.
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: done ? colors.accent : colors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  step.label,
                  style: context.fonts.body(
                    fontSize: 16,
                    color: done ? colors.secondaryText : colors.primaryText,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (tap != null)
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.secondaryText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
