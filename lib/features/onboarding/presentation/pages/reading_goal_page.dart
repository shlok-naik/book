import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_averages.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/soft_pill_button.dart';
import 'paywall_page.dart';

/// New-reader path, Q2 slot: how many books the reader plans to read
/// this year. Only reached by the sign-up branch — a returning sign-in
/// skips straight from account to finish (see [SignInPage]) — so by the
/// time a reader lands here the account already exists, and "continue"
/// saves the answer directly rather than waiting for a later
/// verification step to do it.
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
  late final Future<OnboardingAverages> _averages = widget.profiles
      .fetchAverages();

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  void _continue() {
    final draft = widget.draft.copyWith(
      readingGoal: int.tryParse(_goal.text.trim()),
    );
    // Best-effort, same as the account step's own save — a reader who
    // answered this shouldn't get stuck here just because the write
    // failed, so this doesn't block moving on to the paywall.
    reportingFailure(
      widget.profiles.saveProfile(draft),
      source: 'ReadingGoalPage',
      message: 'Could not save the reading goal answer.',
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaywallPage()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      topContent: const Text('📚', style: TextStyle(fontSize: 96)),
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
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colors.secondaryText,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(label: 'continue', onPressed: _continue),
        ],
      ),
    );
  }
}
