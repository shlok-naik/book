import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../domain/reading_goal.dart';
import '../goal_scope.dart';
import 'goal_picker.dart';

/// Sets, changes or removes the yearly reading goal — reached from
/// settings, the stats page and the add tab. Writes through the one
/// [GoalController] in [GoalScope].
Future<void> showGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'reading_goal'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _GoalSheet(),
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet();

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late int _value = GoalScope.read(context).goal ?? ReadingGoal.suggested;
  bool _busy = false;
  String? _error;

  Future<void> _save(int? goal) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await GoalScope.read(context).setGoal(goal);
    if (!mounted) return;
    if (error != null) {
      AppHaptics.rejected();
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    AppHaptics.accepted();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasGoal = GoalScope.of(context).goal != null;
    final error = _error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'reading goal',
            style: context.fonts.interface(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'how many books do you want to read this year?',
            style: context.fonts.body(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GoalPicker(
            value: _value,
            onChanged: (value) => setState(() => _value = value),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              error,
              style: context.fonts.body(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: _busy ? 'saving…' : 'save',
            onPressed: _busy ? null : () => _save(_value),
          ),
          if (hasGoal) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _busy ? null : () => _save(null),
              child: Text(
                'remove goal',
                style: context.fonts.interface(
                  fontSize: 13,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
