import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/reading_goal.dart';

/// Picks a yearly book count without a text field: a large number between
/// − and + steppers, and a row of common goals to jump to.
///
/// No `TextField` on purpose — onboarding asks for nothing typed (see
/// `intro_flow_test.dart`), and this is shown there. To a screen reader
/// it is one adjustable control; on a keyboard, arrows step it.
class GoalPicker extends StatelessWidget {
  const GoalPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const presets = [6, 12, 24, 52];

  void _set(int next) {
    final clamped = next.clamp(ReadingGoal.min, ReadingGoal.max);
    if (clamped == value) return;
    AppHaptics.selection();
    onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusableActionDetector(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp): _StepIntent(1),
            SingleActivator(LogicalKeyboardKey.arrowRight): _StepIntent(1),
            SingleActivator(LogicalKeyboardKey.arrowDown): _StepIntent(-1),
            SingleActivator(LogicalKeyboardKey.arrowLeft): _StepIntent(-1),
          },
          actions: {
            _StepIntent: CallbackAction<_StepIntent>(
              onInvoke: (intent) => _set(value + intent.step),
            ),
          },
          child: Semantics(
            slider: true,
            label: 'Books to read this year',
            value: '$value',
            increasedValue:
                '${(value + 1).clamp(ReadingGoal.min, ReadingGoal.max)}',
            decreasedValue:
                '${(value - 1).clamp(ReadingGoal.min, ReadingGoal.max)}',
            onIncrease: () => _set(value + 1),
            onDecrease: () => _set(value - 1),
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove,
                  onPressed: value > ReadingGoal.min
                      ? () => _set(value - 1)
                      : null,
                ),
                SizedBox(
                  width: 120,
                  child: Column(
                    children: [
                      Text(
                        '$value',
                        textAlign: TextAlign.center,
                        style: context.fonts.interface(
                          fontSize: 44,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                      Text(
                        value == 1 ? 'book' : 'books',
                        style: context.fonts.interface(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  onPressed: value < ReadingGoal.max
                      ? () => _set(value + 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final preset in presets)
              _PresetChip(
                label: '$preset',
                selected: preset == value,
                onTap: () => _set(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepIntent extends Intent {
  const _StepIntent(this.step);
  final int step;
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: colors.divider)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? colors.accent
                : colors.secondaryText.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label books',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? colors.accent : colors.divider),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              label,
              style: context.fonts.interface(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
