import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// The single styled text field used across every onboarding form —
/// filled with [AppColors.surface], no visible border, [AppRadius.md]
/// corners — so every page's inputs look the same without each page
/// redeclaring the decoration.
class OnboardingTextField extends StatelessWidget {
  const OnboardingTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = GoogleFonts.inter(fontSize: 16, color: colors.primaryText);

    return TextField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      style: style,
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: style.copyWith(color: colors.secondaryText),
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
    );
  }
}
