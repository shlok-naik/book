import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/soft_pill_button.dart';
import 'reading_goal_page.dart';

/// New Q1 slot: picks [ThemeController.mode] before any question is
/// asked, so the rest of the flow already renders in the reader's
/// preferred look. Replaces the old Q1 (reading goal, now pushed to the
/// Q2 slot — see [ReadingGoalPage]).
///
/// A single dropdown rather than a stack of options — this whole page
/// needs to fit in the card without scrolling.
class ThemePreferencePage extends StatelessWidget {
  const ThemePreferencePage({
    super.key,
    required this.session,
    required this.profiles,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;

  static const _labels = {
    ThemeMode.light: '☀️  light',
    ThemeMode.dark: '🌙  dark',
    ThemeMode.system: '⚙️  system',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = GoogleFonts.inter(fontSize: 16, color: colors.primaryText);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return HalfSheetScaffold(
          showBackButton: true,
          progressStep: 2,
          topContent: const Text('🌗', style: TextStyle(fontSize: 96)),
          cardChild: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'pick a look',
                style: GoogleFonts.ebGaramond(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'you can always change this later.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<ThemeMode>(
                initialValue: mode,
                onChanged: (value) {
                  if (value != null) ThemeController.mode.value = value;
                },
                dropdownColor: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                icon: Icon(Icons.expand_more, color: colors.secondaryText),
                style: style,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  for (final entry in _labels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, style: style),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SoftPillButton(
                label: 'continue',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReadingGoalPage(session: session, profiles: profiles),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
