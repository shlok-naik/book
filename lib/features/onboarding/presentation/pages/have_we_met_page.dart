import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/soft_pill_button.dart';
import 'name_page.dart';
import 'sign_in_page.dart';

/// Start of the account dot (step 4): branches the flow depending on
/// whether this reader already has an account.
///
/// "yes" skips straight to signing in — the same passwordless email
/// OTP as the "no" branch ends on, just without the name/description
/// steps first. "no" starts the new-reader path.
class HaveWeMetPage extends StatelessWidget {
  const HaveWeMetPage({
    super.key,
    required this.session,
    required this.profiles,
    required this.draft,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;
  final OnboardingProfileDraft draft;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      topContent: const Text('👋', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'have we met before?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "let us know if you've already got an account.",
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'yes',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SignInPage(
                  session: session,
                  profiles: profiles,
                  draft: draft,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SoftPillButton(
            label: 'no',
            tint: colors.secondaryText,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NamePage(
                  session: session,
                  profiles: profiles,
                  draft: draft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
