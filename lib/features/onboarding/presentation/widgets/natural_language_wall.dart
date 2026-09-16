import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/tilted_marquee_wall.dart';

/// A tilted, auto-scrolling wall of plain sentences — the sort of thing a
/// reader might actually type on the add tab — in italic Inter so it reads
/// as conversation rather than command syntax.
class NaturalLanguageWall extends StatelessWidget {
  const NaturalLanguageWall({super.key});

  static const _rows = [
    [
      'started the shining yesterday',
      'i read up to pg 28',
      'finished circe last night',
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
