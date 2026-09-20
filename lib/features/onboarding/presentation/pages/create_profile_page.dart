import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../../profile/presentation/profile_identity_controller.dart';
import '../../../profile/presentation/widgets/edit_profile_sheet.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'secure_library_page.dart';

/// "what's your name?" — the first question onboarding asks, right after the
/// welcome, so the reader has a name before being shown around.
///
/// A name is required and there is no skip. Nothing else is: the shelf
/// already exists (the reader was signed in anonymously before the first
/// frame), and the email comes on the next screen, skippable.
class CreateProfilePage extends StatefulWidget {
  const CreateProfilePage({super.key});

  @override
  State<CreateProfilePage> createState() => _CreateProfilePageState();
}

class _CreateProfilePageState extends State<CreateProfilePage> {
  final _displayName = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ProfileIdentityController.save(
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
    setState(() => _busy = false);
    AppHaptics.accepted();
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'onboarding_secure_library'),
          builder: (_) => const SecureLibraryPage(),
        ),
      ),
    );
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
            "what's your name?",
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'your shelf already exists — no password, nothing to sign up '
            'for. this is just what we call you.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ProfileNameField(
            controller: _displayName,
            onSubmit: () => unawaited(_continue()),
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
        ],
      ),
    );
  }
}
