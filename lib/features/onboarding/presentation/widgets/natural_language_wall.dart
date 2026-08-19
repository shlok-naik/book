import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/tilted_marquee_wall.dart';

/// [CommandWall]'s Pro-tier counterpart: the same tilted, auto-scrolling
/// wall, but the chips are natural-language snippets — the sort of
/// thing a reader might actually type — in place of exact command
/// syntax.
///
/// Styled in italic Inter rather than [CommandWall]'s monospace, so the
/// two walls read as visually distinct at a glance: precise commands
/// versus conversational language.
class NaturalLanguageWall extends StatelessWidget {
  const NaturalLanguageWall({super.key});

  static const _rows = [
    [
      'started the shining yesterday',
      'i read up to pg 28',
      'recommend a book like this',
    ],
    ['i liked the story', 'the pacing was alright ig', 'i like the characters'],
    ['finished dune, loved it', 'rate circe 5 stars', 'kinda confusing tbh'],
  ];

  @override
  Widget build(BuildContext context) {
    return TiltedMarqueeWall(
      rows: [
        for (final row in _rows)
          [for (final phrase in row) _PhraseChip(phrase)],
      ],
    );
  }
}

class _PhraseChip extends StatelessWidget {
  const _PhraseChip(this.phrase);

  final String phrase;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '"$phrase"',
        style: GoogleFonts.inter(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: colors.primaryText,
        ),
      ),
    );
  }
}
