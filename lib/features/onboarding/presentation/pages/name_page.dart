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
import 'description_page.dart';

/// New-reader path, account dot (step 4): what to call them.
class NamePage extends StatefulWidget {
  const NamePage({
    super.key,
    required this.session,
    required this.profiles,
    required this.draft,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;
  final OnboardingProfileDraft draft;

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      topContent: const Text('✍️', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "what's your name?",
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OnboardingTextField(controller: _name, hintText: 'name'),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'continue',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DescriptionPage(
                  session: widget.session,
                  profiles: widget.profiles,
                  draft: widget.draft.copyWith(name: _name.text.trim()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
