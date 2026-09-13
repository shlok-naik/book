import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/domain/reading_goal.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_picker.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import 'one_more_thing_page.dart';

/// Onboarding's second question: how many books this year. Picked with
/// steppers and presets — no text field, like everything else in the intro
/// — and saved through the same [GoalController] the stats page and
/// settings use, so it's a shortcut to a setting rather than separate state.
///
/// Skippable: a goal is a nice-to-have, and the intro never gates on an
/// answer. A save that fails says so and still lets the reader move on.
class ReadingGoalPage extends StatefulWidget {
  const ReadingGoalPage({super.key});

  @override
  State<ReadingGoalPage> createState() => _ReadingGoalPageState();
}

class _ReadingGoalPageState extends State<ReadingGoalPage> {
  int _value = ReadingGoal.suggested;
  bool _busy = false;
  String? _error;

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'onboarding_one_more_thing'),
        builder: (_) => const OneMoreThingPage(),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await GoalScope.read(context).setGoal(_value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) _next();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final error = _error;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 3,
      topContent: const Text('🎯', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'set a goal',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'how many books do you want to read this year? you can change '
            'it any time.',
            style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: _busy ? 'saving…' : 'continue',
            onPressed: _busy ? null : _save,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _busy ? null : _next,
            child: Text(
              'skip for now',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
