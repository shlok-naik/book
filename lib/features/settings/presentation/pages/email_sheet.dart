import 'package:flutter/material.dart';

import '../../../../core/auth/session_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';

/// Asks for an email, then the code sent to it, and attaches the result
/// to the reader's existing account.
///
/// Serves both account rows, because underneath they are the same two
/// Supabase calls: giving an anonymous shelf its first address, and
/// moving a linked one to a different address. Which of the two it is
/// changes only the wording — see [_EmailSheet.mode].
///
/// How the sheet ended.
class EmailSheetResult {
  const EmailSheetResult.linked() : existingAccount = null;
  const EmailSheetResult.existing(PendingAccount this.existingAccount);

  /// Set when the email already had its own library: the reader signed in
  /// to it, and now has to choose which library to keep.
  final PendingAccount? existingAccount;
}

/// Returns [EmailSheetResult.linked] once the address is verified on this
/// account, [EmailSheetResult.existing] once the reader signed in to the
/// account that already owns it, or null if they backed out.
Future<EmailSheetResult?> showEmailSheet(
  BuildContext context, {
  required SessionService session,
  String? initialEmail,
}) {
  return showModalBottomSheet<EmailSheetResult>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => _EmailSheet(
      session: session,
      mode: session.isAnonymous ? _EmailMode.link : _EmailMode.change,
      initialEmail: initialEmail,
    ),
  );
}

/// Which of the two jobs the sheet is doing. The mechanism is identical
/// either way; only the copy differs, and it differs enough to matter —
/// "back up with email" is an offer, "change email" is an edit.
enum _EmailMode {
  /// No address yet: the shelf lives on this device only.
  link,

  /// Already linked, moving to a different address.
  change,
}

/// The two-step email/code card behind [showEmailSheet].
///
/// This is the *only* reason a reader ever types an email into cactus,
/// and what it does is deliberately narrow: it links an identity to the
/// account they already have, keeping the same uid and therefore the
/// same shelf, streaks, memories and entitlements. It is not a sign-in —
/// signing in would provision a different account and abandon this one.
/// See [SessionService.linkEmail].
class _EmailSheet extends StatefulWidget {
  const _EmailSheet({
    required this.session,
    required this.mode,
    this.initialEmail,
  });

  final SessionService session;
  final _EmailMode mode;

  /// Prefilled when the reader already typed an address somewhere else —
  /// onboarding's profile screen. They still confirm the code.
  final String? initialEmail;

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();

  /// True once "send code" succeeds — that's what switches the card from
  /// the email step to the code step.
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  /// True when the email turned out to belong to another account and the
  /// code sent is a sign-in code for it, not a link code for this one.
  bool _existing = false;

  String get _title => switch (widget.mode) {
    _EmailMode.link => 'back up with email',
    _EmailMode.change => 'change email',
  };

  String get _blurb => switch (widget.mode) {
    _EmailMode.link =>
      'your shelf stays exactly as it is — this just gives it a way '
          'back to you on another device.',
    _EmailMode.change =>
      'your shelf stays exactly as it is — only the address it answers '
          'to changes.',
  };

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter an email first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.linkEmail(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
    } on EmailInUseException {
      // Only an anonymous shelf can join an existing account; a linked one
      // changing its address to someone else's is simply refused.
      if (widget.mode != _EmailMode.link) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'Email already in use.';
        });
        return;
      }
      try {
        await widget.session.sendSignInCode(_email.text.trim());
        if (!mounted) return;
        setState(() {
          _existing = true;
          _codeSent = true;
          _busy = false;
        });
      } on SessionException catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on SessionException catch (error) {
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
      if (_existing) {
        final account = await widget.session.verifySignInCode(
          email: _email.text.trim(),
          code: _code.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pop(EmailSheetResult.existing(account));
        return;
      }
      await widget.session.verifyEmailCode(
        email: _email.text.trim(),
        code: _code.text.trim(),
      );
      if (!mounted) return;
      // No RevenueCat/Crashlytics re-identify on the way out: this
      // preserves the uid those were already told about at startup, so
      // there is nothing to update. That is the whole point of doing it
      // with `updateUser` rather than a fresh sign-in.
      Navigator.of(context).pop(const EmailSheetResult.linked());
    } on SessionException catch (error) {
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
    final error = _error;

    return Padding(
      // Lifts the card clear of the keyboard the field below summons.
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _title,
            style: context.fonts.interface(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            !_codeSent
                ? _blurb
                : _existing
                ? 'that email already has a cactus library. we sent it a code '
                      '— sign in, then choose which library to keep.'
                : 'check your email for the code.',
            style: context.fonts.body(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!_codeSent)
            _SheetField(
              controller: _email,
              hintText: widget.mode == _EmailMode.link ? 'email' : 'new email',
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _sendCode(),
            )
          else
            _SheetField(
              controller: _code,
              hintText: 'code',
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _verifyCode(),
            ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              error,
              style: context.fonts.body(
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

/// A plain, calm text field on the sheet's own surface — the app has no
/// other form, so this stays local rather than becoming a shared widget
/// on the strength of one call site.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hintText,
    required this.keyboardType,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.fonts.body(fontSize: 15, color: colors.primaryText);

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      // Enter submits without closing the keyboard (a TextField's default
      // is to unfocus on the action button).
      onEditingComplete: () {},
      style: style,
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: style.copyWith(color: colors.secondaryText),
        filled: true,
        fillColor: colors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}
