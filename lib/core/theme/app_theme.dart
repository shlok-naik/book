import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_color_theme.dart';
import 'app_colors.dart';
import 'app_font_theme.dart';
import 'app_fonts.dart';

/// Central Light/Dark [ThemeData] for the Mono & Teal design system.
/// Type comes from the reader's [AppFontTheme] through [AppFonts].
abstract final class AppTheme {
  // Getters, not cached static fields — a static field is built once and
  // held for the rest of the session, which Dart's hot reload cannot
  // refresh (only a hot restart re-runs static initializers), so a
  // color-only edit would silently keep showing the old theme until a
  // full restart. Rebuilding on every access costs nothing worth
  // noticing and keeps hot reload actually reflecting AppColors.
  //
  // [light]/[dark] always build the default forest accent — every
  // existing call site (most of the test suite included) expects that
  // without passing anything. The app itself instead calls
  // [lightWith]/[darkWith] with the reader's own [AppColorTheme], read
  // from `AppColorThemeController`.
  static ThemeData get light =>
      _build(AppColors.light, AppFonts.original, Brightness.light);
  static ThemeData get dark =>
      _build(AppColors.dark, AppFonts.original, Brightness.dark);

  /// The app's own light theme: the reader's accent and font set. [fonts]
  /// defaults to the original set, so existing callers keep their look.
  static ThemeData lightWith(
    AppColorTheme theme, [
    AppFontTheme fonts = AppFontTheme.original,
  ]) => _build(
    AppColors.light.copyWith(accent: theme.lightAccent),
    AppFonts(fonts),
    Brightness.light,
  );
  static ThemeData darkWith(
    AppColorTheme theme, [
    AppFontTheme fonts = AppFontTheme.original,
  ]) => _build(
    AppColors.dark.copyWith(accent: theme.darkAccent),
    AppFonts(fonts),
    Brightness.dark,
  );

  static ThemeData _build(
    AppColors colors,
    AppFonts fonts,
    Brightness brightness,
  ) {
    final base = ThemeData(brightness: brightness, useMaterial3: true);

    final textTheme = base.textTheme
        .apply(bodyColor: colors.primaryText, displayColor: colors.primaryText)
        .copyWith(
          displayLarge: fonts.bookTitle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
          headlineMedium: fonts.bookTitle(
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
      textTheme: GoogleFonts.getTextTheme(fonts.theme.bodyFamily, textTheme)
          .copyWith(
            displayLarge: textTheme.displayLarge,
            headlineMedium: textTheme.headlineMedium,
          ),
      extensions: [colors, fonts],
    );
  }
}
