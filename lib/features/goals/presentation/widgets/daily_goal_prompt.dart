import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/daily_goal.dart';
import '../daily_goal_controller.dart';

/// The add tab's daily habit, under the book being read: "have you read 10
/// minutes today?" and a tick to answer it.
///
/// Nothing here measures time — the app never watches the reader read, so
/// the question is asked plainly and the answer is theirs. Tapping the tick
/// marks today (tapping again unmarks it); tapping the question changes how
/// many minutes it asks for. The yearly books goal it replaced is still
/// one tap away on the stats tab, where the rest of the numbers live.
class DailyGoalPrompt extends StatelessWidget {
  const DailyGoalPrompt({super.key, this.now});

  /// Tests pin today.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = now ?? DateTime.now();

    return ValueListenableBuilder<DailyGoal>(
      valueListenable: DailyGoalController.goal,
      builder: (context, goal, _) {
        final done = goal.isDone(today);
        final streak = goal.streak(today);

        void toggle() {
          if (done) {
            AppHaptics.selection();
          } else {
            AppHaptics.accepted();
          }
          unawaited(DailyGoalController.toggle(today));
        }

        return Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Daily goal: ${goal.minutes} minutes. Change it',
                excludeSemantics: true,
                onTap: () => unawaited(showDailyGoalSheet(context)),
                child: InkWell(
                  key: const ValueKey('daily-goal-question'),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () {
                    AppHaptics.selection();
                    unawaited(showDailyGoalSheet(context));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          done
                              ? 'you read ${goal.minutes} minutes today'
                              : 'have you read ${goal.minutes} minutes today?',
                          style: context.fonts.interface(
                            fontSize: 14,
                            color: colors.primaryText,
                          ),
                        ),
                        if (streak > 0)
                          Text(
                            '$streak ${streak == 1 ? 'day' : 'days'} in a row',
                            style: context.fonts.body(
                              fontSize: 12,
                              color: colors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              checked: done,
              label: done ? 'Read today — tap to undo' : 'Mark today as read',
              excludeSemantics: true,
              onTap: toggle,
              child: InkResponse(
                key: const ValueKey('daily-goal-done'),
                onTap: toggle,
                radius: 24,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? colors.accent : Colors.transparent,
                    border: Border.all(
                      color: done ? colors.accent : colors.secondaryText,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 20,
                    color: done ? colors.background : colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Picks how many minutes a day the reader is aiming for — the sheet the
/// question itself opens.
Future<void> showDailyGoalSheet(BuildContext context) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ValueListenableBuilder<DailyGoal>(
          valueListenable: DailyGoalController.goal,
          builder: (context, goal, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'minutes a day',
                  style: context.fonts.interface(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final minutes in DailyGoal.minuteOptions)
                    _MinuteChip(
                      minutes: minutes,
                      selected: goal.minutes == minutes,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'a small number you can keep beats a big one you cannot.',
                style: context.fonts.body(
                  fontSize: 13,
                  height: 1.5,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MinuteChip extends StatelessWidget {
  const _MinuteChip({required this.minutes, required this.selected});

  final int minutes;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    void select() {
      AppHaptics.selection();
      unawaited(DailyGoalController.setMinutes(minutes));
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '$minutes minutes a day',
      excludeSemantics: true,
      onTap: select,
      child: InkWell(
        key: ValueKey('daily-goal-minutes-$minutes'),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: select,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: selected ? colors.accent : Colors.transparent,
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
            ),
          ),
          child: Text(
            '$minutes min',
            style: context.fonts.interface(
              fontSize: 14,
              color: selected ? colors.background : colors.primaryText,
            ),
          ),
        ),
      ),
    );
  }
}
