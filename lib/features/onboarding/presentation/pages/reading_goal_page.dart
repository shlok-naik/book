import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_averages.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import 'reading_time_page.dart';

/// Step 2 (Q1) of the post-tutorial sequence: how many books the reader
/// plans to read this year.
class ReadingGoalPage extends StatefulWidget {
  const ReadingGoalPage({
    super.key,
    required this.session,
    required this.profiles,
    this.draft = const OnboardingProfileDraft(),
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;
  final OnboardingProfileDraft draft;

  @override
  State<ReadingGoalPage> createState() => _ReadingGoalPageState();
}

class _ReadingGoalPageState extends State<ReadingGoalPage> {
  final _goal = TextEditingController();
  late final Future<OnboardingAverages> _averages = widget.profiles.fetchAverages();

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 2,
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'how many books do you plan to read this year?',
            style: GoogleFonts.ebGaramond(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OnboardingTextField(
            controller: _goal,
            hintText: 'e.g. 20',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<OnboardingAverages>(
            future: _averages,
            builder: (context, snapshot) {
              final goal = snapshot.data?.readingGoal;
              // Hidden rather than showing a placeholder while
              // loading/on failure — this is a nice-to-have aside, not
              // something worth a spinner or an error of its own.
              if (goal == null) return const SizedBox.shrink();
              return Text(
                'the average reader here plans for $goal books this year.',
                style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReadingTimePage(
                  session: widget.session,
                  profiles: widget.profiles,
                  draft: widget.draft.copyWith(
                    readingGoal: int.tryParse(_goal.text.trim()),
                  ),
                ),
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text('continue', style: GoogleFonts.inter(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
