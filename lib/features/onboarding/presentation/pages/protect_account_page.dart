import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import 'finish_page.dart';

/// New-reader path, account dot (step 4): passwordless email sign-up.
/// "send code" asks Supabase to email a one-time code to the given
/// address; "verify" checks it and provisions the account on the spot
/// if that email hasn't signed up before — see
/// [SessionService.sendEmailConfirmation]. Once that succeeds, [draft]
/// (everything collected since Q1) is saved against the new account.
class ProtectAccountPage extends StatefulWidget {
  const ProtectAccountPage({
    super.key,
    required this.session,
    required this.profiles,
    required this.draft,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;
  final OnboardingProfileDraft draft;

  @override
  State<ProtectAccountPage> createState() => _ProtectAccountPageState();
}

class _ProtectAccountPageState extends State<ProtectAccountPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// True once "send code" succeeds — that's what switches the card
  /// from the email step to the code step.
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'enter an email first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.sendEmailConfirmation(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
    } on OnboardingException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _verifyCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.verifyEmailCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
      // The account itself is what matters most here — a reader who
      // successfully verified shouldn't get stuck on an error screen
      // just because saving the profile details failed, so this is
      // best-effort and doesn't block moving on.
      try {
        await widget.profiles.saveProfile(widget.draft);
      } on OnboardingException {
        // Ignored — see above.
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FinishPage()),
      );
    } on OnboardingException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 4,
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "let's protect your account",
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _codeSent
                ? 'check your email for the code.'
                : "we'll send a code to verify it's really you.",
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_codeSent) ...[
            OnboardingTextField(
              controller: _email,
              hintText: 'email',
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _sendCode(),
            ),
          ] else ...[
            OnboardingTextField(
              controller: _code,
              hintText: 'code',
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _verifyCode(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _verifyCode : _sendCode),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              _busy
                  ? (_codeSent ? 'verifying…' : 'sending…')
                  : (_codeSent ? 'verify' : 'send code'),
              style: GoogleFonts.inter(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
