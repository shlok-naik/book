import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/session_service.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/soft_pill_button.dart';
import 'finish_page.dart';
import 'theme_preference_page.dart';

/// Returning-reader path, account step (step 2): the "have we met
/// before" yes-branch. Same passwordless email OTP as
/// [ProtectAccountPage] — `signInWithOtp`/`verifyOTP` sign an existing
/// reader straight in, no password involved.
///
/// A returning reader doesn't need the rest of onboarding — nothing's
/// been collected to save (account comes before any question is asked),
/// so after picking a theme (Q1), this skips Q2, the paywall, "one more
/// thing", and the founder's note, landing straight on [FinishPage].
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.session});

  final SessionService session;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
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
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThemePreferencePage(
            onContinue: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FinishPage(bypass: (from: 2, to: 5)),
              ),
            ),
          ),
        ),
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
      progressStep: 2,
      topContent: const Text('🔑', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'welcome back',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _codeSent
                ? 'enter the code below.'
                : "we'll send a code to sign you in.",
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
              style: GoogleFonts.inter(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: _busy
                ? (_codeSent ? 'verifying…' : 'sending…')
                : (_codeSent ? 'verify' : 'send code'),
            onPressed: _busy ? null : (_codeSent ? _verifyCode : _sendCode),
          ),
        ],
      ),
    );
  }
}
