import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/soft_pill_button.dart';
import 'protect_account_page.dart';

/// New-reader path, account dot (step 4): something fun about them,
/// entirely optional — the last answer collected before the account
/// itself is created.
class DescriptionPage extends StatefulWidget {
  const DescriptionPage({
    super.key,
    required this.session,
    required this.profiles,
    required this.draft,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;
  final OnboardingProfileDraft draft;

  @override
  State<DescriptionPage> createState() => _DescriptionPageState();
}

class _DescriptionPageState extends State<DescriptionPage> {
  final _description = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      topContent: const Text('💬', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "what's something fun about you?",
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'optional — skip it if you like.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OnboardingTextField(
            controller: _description,
            hintText: 'description (optional)',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'continue',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProtectAccountPage(
                  session: widget.session,
                  profiles: widget.profiles,
                  draft: widget.draft.copyWith(
                    description: _description.text.trim(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
