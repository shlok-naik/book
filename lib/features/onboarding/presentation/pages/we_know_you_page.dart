import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/soft_pill_button.dart';
import 'finish_page.dart';
import 'have_we_met_page.dart';

const _bypass = (from: 3, to: 5);

/// Shown when a reader picks "no" on [HaveWeMetPage] — I don't have an
/// account — but the email they verify on [ProtectAccountPage] turns
/// out to already belong to one (see
/// `SessionService.isExistingAccount`). Rather than silently signing
/// them into a stranger's session or quietly failing, this asks them to
/// confirm it's really their own account before continuing.
///
/// "yes and sign in" — the OTP verification that got here already
/// created a real session, so this just continues the same way
/// [SignInPage] does: straight to [FinishPage], skipping the rest of
/// onboarding since nothing new needs collecting for an existing
/// reader.
///
/// "no" signs back out (it isn't their account) and returns to
/// [HaveWeMetPage] — the same fork this whole detour started from —
/// rather than assuming they meant "try a different email" (that's
/// what its own "yes" branch, [SignInPage], is for).
class WeKnowYouPage extends StatelessWidget {
  const WeKnowYouPage({
    super.key,
    required this.session,
    required this.profiles,
    required this.draft,
    this.name,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;

  /// Carried only so "no" can hand it straight back to a fresh
  /// [HaveWeMetPage] — the name/description already collected this
  /// session shouldn't have to be re-entered just because the first
  /// email tried turned out to be someone else's account.
  final OnboardingProfileDraft draft;

  /// The reader's own stored name, fetched via
  /// `OnboardingProfileRepository.fetchName`. Null when the existing
  /// account never set one — the confirmation line falls back to a
  /// name-free phrasing rather than disappearing entirely, so this
  /// screen never reads as broken.
  final String? name;

  void _signInAsExisting(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FinishPage()));
  }

  Future<void> _backToHaveWeMet(BuildContext context) async {
    // Best-effort: the point is to get back to the email question, and
    // a sign-out that failed must not strand the reader on this screen.
    try {
      await session.signOut();
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'WeKnowYouPage',
        'Signing out before retrying with another email failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            HaveWeMetPage(session: session, profiles: profiles, draft: draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      progressStep: 3,
      bypass: _bypass,
      topContent: const Text('❓', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'wait… we do know you.',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name != null
                ? "you're $name right?"
                : 'this is already you, right?',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'yes and sign in',
            onPressed: () => _signInAsExisting(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          SoftPillButton(
            label: 'no',
            tint: colors.secondaryText,
            onPressed: () => _backToHaveWeMet(context),
          ),
        ],
      ),
    );
  }
}
