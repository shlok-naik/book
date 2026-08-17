import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A small rounded status chip — same style and position whether the
/// command succeeded or was rejected, so only the message text differs.
class ConfirmationPill extends StatelessWidget {
  const ConfirmationPill({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          message,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            color: colors.primaryText,
          ),
        ),
      ),
    );
  }
}
