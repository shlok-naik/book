import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_font_theme.dart';

/// The reader's [AppFontTheme] as text styles, exposed as a
/// [ThemeExtension] the same way [AppColors] exposes colors — widgets ask
/// `context.fonts.interface(...)` rather than naming a family, so a change
/// on the customisation page reaches every screen at once (anything that
/// read it depends on the [Theme], and rebuilds when it changes).
///
/// Each method takes the same arguments `GoogleFonts.jetBrainsMono(...)`
/// and friends do, so a call site swaps one for the other unchanged.
@immutable
class AppFonts extends ThemeExtension<AppFonts> {
  const AppFonts(this.theme);

  static const original = AppFonts(AppFontTheme.original);

  final AppFontTheme theme;

  /// Page titles, section headings, labels, pills, the command line.
  TextStyle interface({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    List<ui.Shadow>? shadows,
    List<ui.FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) => GoogleFonts.getFont(
    theme.interfaceFamily,
    textStyle: textStyle,
    color: color,
    backgroundColor: backgroundColor,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    height: height,
    shadows: shadows,
    fontFeatures: fontFeatures,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
  );

  /// Running text.
  TextStyle body({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    List<ui.Shadow>? shadows,
    List<ui.FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) => GoogleFonts.getFont(
    theme.bodyFamily,
    textStyle: textStyle,
    color: color,
    backgroundColor: backgroundColor,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    height: height,
    shadows: shadows,
    fontFeatures: fontFeatures,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
  );

  /// Book titles — tiles, covers, the currently-reading card, the book page.
  TextStyle bookTitle({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    List<ui.Shadow>? shadows,
    List<ui.FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) => GoogleFonts.getFont(
    theme.bookTitleFamily,
    textStyle: textStyle,
    color: color,
    backgroundColor: backgroundColor,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    height: height,
    shadows: shadows,
    fontFeatures: fontFeatures,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
  );

  @override
  AppFonts copyWith({AppFontTheme? theme}) => AppFonts(theme ?? this.theme);

  /// Typefaces don't interpolate; the switch happens at the halfway point.
  @override
  AppFonts lerp(ThemeExtension<AppFonts>? other, double t) =>
      other is AppFonts && t >= 0.5 ? other : this;

  @override
  bool operator ==(Object other) => other is AppFonts && other.theme == theme;

  @override
  int get hashCode => theme.hashCode;
}

extension AppFontsContext on BuildContext {
  /// The reader's fonts. Falls back to the original set under a [Theme]
  /// built without the extension (a bare test harness), rather than
  /// throwing the way a missing color extension would.
  AppFonts get fonts =>
      Theme.of(this).extension<AppFonts>() ?? AppFonts.original;
}
