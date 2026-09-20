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
import '../../../settings/presentation/widgets/membership_card.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';

/// "want to secure your library?" — the optional email step. Linking an
/// email keeps the shelf if the phone is lost; "skip" walks straight on to
/// the tour, and it can be done later from the profile screen.
class SecureLibraryPage extends StatefulWidget {
  const SecureLibraryPage({super.key});

  @override
  State<SecureLibraryPage> createState() => _SecureLibraryPageState();
}

class _SecureLibraryPageState extends State<SecureLibraryPage> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _next() {
    if (!mounted) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'onboarding_buttons_tutorial'),
          builder: (_) => const ButtonsTutorialPage(),
        ),
      ),
    );
  }

  Future<void> _link() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      AppHaptics.rejected();
      return;
    }
    setState(() => _busy = true);
    // Linking needs the code Supabase mails — the same sheet the profile
    // screen uses, so there is one verified path to an address.
    try {
      await editAccountEmail(
        context,
        session: SessionScope.of(context),
        initialEmail: email,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SecureLibraryPage',
        'Linking an email during onboarding failed.',
        error: error,
        stackTrace: stackTrace,
      );
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
      topContent: const TourIcon(Icons.lock_outline),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'want to secure your library?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'link an email and your books stay yours if you lose this '
            'phone or sign in somewhere new. no password.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('onboarding-email-field'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => unawaited(_link()),
            style: GoogleFonts.inter(fontSize: 16, color: colors.primaryText),
            decoration: InputDecoration(
              labelText: 'email',
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
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: _busy ? 'linking…' : 'link email',
            onPressed: _busy ? null : () => unawaited(_link()),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            key: const ValueKey('onboarding-email-skip'),
            onPressed: _busy ? null : _next,
            child: Text(
              'skip',
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
