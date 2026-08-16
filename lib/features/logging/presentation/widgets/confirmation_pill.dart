import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/log_command_parser.dart';

/// A small rounded status chip echoing the app's pill buttons —
/// solid cobalt when a command was understood, quiet outline otherwise.
class ConfirmationPill extends StatelessWidget {
  const ConfirmationPill({super.key, required this.result});

  final ParsedLogCommand result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final recognized = result.recognized;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: recognized ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          result.message,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            color: recognized ? Colors.white : colors.secondaryText,
          ),
        ),
      ),
    );
  }
}
