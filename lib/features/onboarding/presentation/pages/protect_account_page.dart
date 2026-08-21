import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/analytics/app_analytics.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/diagnostics/crash_reporter.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../../domain/onboarding_profile_draft.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/onboarding_text_field.dart';
import '../widgets/soft_pill_button.dart';
import 'reading_goal_page.dart';
import 'we_know_you_page.dart';

/// New-reader path, account step (step 3, right after Q1): passwordless
/// email sign-up. "send code" asks Supabase to email a one-time code to
/// the given address; "verify" checks it and provisions the account on
/// the spot if that email hasn't signed up before — see
/// [SessionService.sendEmailConfirmation]. Once that succeeds, [draft]
/// (the name/description collected so far) is saved against the new
/// account, and the flow continues into Q2 (reading goal) before the
/// paywall.
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

      // The "no" branch assumes a fresh account, but the email
      // verified above may already belong to one — Supabase can't
      // tell us that up front (see `SessionService.isExistingAccount`
      // for why), only after the fact. Catching it here, rather than
      // silently treating a stranger's account as a blank slate, is
      // the whole reason `WeKnowYouPage` exists.
      if (widget.session.isExistingAccount) {
        String? existingName;
        try {
          existingName = await widget.profiles.fetchName();
        } on OnboardingException {
          existingName = null;
        }
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'onboarding_we_know_you'),
            builder: (_) => WeKnowYouPage(
              session: widget.session,
              profiles: widget.profiles,
              draft: widget.draft,
              name: existingName,
            ),
          ),
        );
        setState(() => _busy = false);
        return;
      }

      // The account itself is what matters most here — a reader who
      // successfully verified shouldn't get stuck on an error screen
      // just because saving the profile details failed, so this is
      // best-effort and doesn't block moving on.
      try {
        await widget.profiles.saveProfile(widget.draft);
      } on OnboardingException {
        // Ignored — see above.
      }
      // Best-effort and fire-and-forget for the same reason: links
      // this new account to a RevenueCat purchaser id, but never
      // blocks onboarding on it completing.
      final userId = widget.session.userId;
      if (userId != null) {
        CrashReporter.identify(userId);
        AppAnalytics.identify(userId);
        reportingFailure(
          const PurchasesService().identify(userId),
          source: 'ProtectAccountPage',
          message: 'Could not link this account to its RevenueCat identity.',
        );
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_reading_goal'),
          builder: (_) => ReadingGoalPage(
            session: widget.session,
            profiles: widget.profiles,
            draft: widget.draft,
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
      progressStep: 3,
      topContent: const Text('🔒', style: TextStyle(fontSize: 96)),
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
