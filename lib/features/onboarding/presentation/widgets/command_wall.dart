import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/tilted_marquee_wall.dart';

/// A tilted wall of the app's commands, each row auto-scrolling
/// sideways at its own speed and direction — the "add-a-book" tutorial
/// step's demonstration of what the log page's command line looks like,
/// in place of the screenshot Pushr's equivalent step uses.
///
/// The whole stack is rotated a few degrees so each row reads as sitting
/// diagonally below the one above it, rather than a flat, static list.
class CommandWall extends StatelessWidget {
  const CommandWall({super.key});

  static const _rows = [
    [
      'start The Shining',
      'start Dune',
      'start Circe',
      'start 1984',
      'start Emma',
      'start The Hobbit',
    ],
    [
      'update Dune 120',
      'update Emma 40',
      'update 1984 210',
      'update Circe 88',
      'update The Hobbit 150',
    ],
    [
      'finish The Shining',
      'rate Dune 4.5',
      'delete Emma',
      'rate Circe 5',
      'finish 1984',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    // The tilt, per-row speeds and alternating directions all live in
    // TiltedMarqueeWall now — shared with the paywall's feature pills,
    // so the two walls can't drift apart.
    return TiltedMarqueeWall(
      rows: [
        for (final row in _rows)
          [for (final command in row) _CommandChip(command)],
      ],
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip(this.command);

  final String command;

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
        command,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          color: colors.primaryText,
        ),
      ),
    );
  }
}
