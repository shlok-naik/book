import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/auth/session_scope.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../../profile/presentation/profile_identity_controller.dart';
import '../../../profile/presentation/widgets/edit_profile_sheet.dart';
import '../../../settings/presentation/widgets/membership_card.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';

/// "make it yours" — the one onboarding screen that asks for anything: a
/// name, a username, and an email if the reader wants their shelf backed
/// up. It comes first, right after the welcome, so the reader has a name
/// before they are shown around.
///
/// All three are optional, and the shelf already exists either way: the
/// reader was signed in anonymously before the first frame, so this is a
/// profile, not a gate. "not now" moves straight on to the tour.
class CreateProfilePage extends StatefulWidget {
  const CreateProfilePage({super.key});

  @override
  State<CreateProfilePage> createState() => _CreateProfilePageState();
}

class _CreateProfilePageState extends State<CreateProfilePage> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  void _next() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'onboarding_buttons_tutorial'),
        builder: (_) => const ButtonsTutorialPage(),
      ),
    );
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ProfileIdentityController.save(
      username: _username.text,
      displayName: _displayName.text,
    );
    if (!mounted) return;
    if (error != null) {
      AppHaptics.rejected();
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }

    // An email is the reader's own choice, and linking it needs the code
    // Supabase mails — the same sheet settings uses, so there is one
    // verified path to an address rather than two.
    if (_email.text.trim().isNotEmpty) {
      try {
        await editAccountEmail(
          context,
          session: SessionScope.of(context),
          initialEmail: _email.text.trim(),
        );
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'CreateProfilePage',
          'Linking an email during onboarding failed.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    AppHaptics.accepted();
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      topContent: const TourIcon(Icons.badge_outlined),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'make it yours',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'your shelf already exists — no password, nothing to sign up '
            'for. this is just what we call you. all of it is optional.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ProfileNameFields(
            username: _username,
            displayName: _displayName,
            onSubmit: () => unawaited(_continue()),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('onboarding-email-field'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: GoogleFonts.inter(fontSize: 16, color: colors.primaryText),
            decoration: InputDecoration(
              labelText: 'email, to keep your library safe',
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                color: colors.secondaryText,
              ),
              filled: true,
              fillColor: colors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              style: GoogleFonts.inter(fontSize: 14, color: colors.primaryText),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: _busy ? 'saving…' : 'continue',
            onPressed: _busy ? null : () => unawaited(_continue()),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const ValueKey('onboarding-profile-skip'),
            onPressed: _busy ? null : _next,
            child: Text(
              'not now',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
