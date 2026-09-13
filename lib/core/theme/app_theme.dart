import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Central Light/Dark [ThemeData] for the Mono & Teal design system.
/// Fraunces for headings/display, Inter for body/UI.
abstract final class AppTheme {
  // Getters, not cached static fields — a static field is built once and
  // held for the rest of the session, which Dart's hot reload cannot
  // refresh (only a hot restart re-runs static initializers), so a
  // color-only edit would silently keep showing the old theme until a
  // full restart. Rebuilding on every access costs nothing worth
  // noticing and keeps hot reload actually reflecting AppColors.
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

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
