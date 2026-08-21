import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/soft_pill_button.dart';
import 'finish_page.dart';

/// Third finish-category screen — a short personal note, signed by
/// name, before the last "you're all set" beat.
class FoundersNotePage extends StatelessWidget {
  const FoundersNotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 5,
      // Inter itself resolves a monochrome glyph for the bare U+2764
      // codepoint, so `fontFamilyFallback` never even gets consulted —
      // this has to name the color emoji font directly as the primary
      // family to force it, unlike the other topContent emoji here,
      // none of which collide with a text-style glyph inside Inter.
      topContent: const Text(
        '❤️',
        style: TextStyle(fontSize: 96, fontFamily: 'Noto Color Emoji'),
      ),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'a note from the founder',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'i built cactus cuz every other tracker made reading feel '
            'like math homework (lol). thanks for giving it a try - i '
            'hope you love it as much as i do.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '- shlok',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'continue',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'onboarding_finish'),
                builder: (_) => const FinishPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
