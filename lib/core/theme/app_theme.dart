import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Central Light/Dark [ThemeData] for the Mono & Teal design system.
/// Fraunces for headings/display, Inter for body/UI.
abstract final class AppTheme {
  static ThemeData light = _build(AppColors.light, Brightness.light);
  static ThemeData dark = _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    final textTheme = base.textTheme
        .apply(bodyColor: colors.primaryText, displayColor: colors.primaryText)
        .copyWith(
          displayLarge: GoogleFonts.fraunces(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
          headlineMedium: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.divider,
      colorScheme: base.colorScheme.copyWith(
        brightness: brightness,
        surface: colors.surface,
        primary: colors.accent,
        onSurface: colors.primaryText,
      ),
      textTheme: GoogleFonts.interTextTheme(textTheme).copyWith(
        displayLarge: textTheme.displayLarge,
        headlineMedium: textTheme.headlineMedium,
      ),
      extensions: [colors],
    );
  }
}
