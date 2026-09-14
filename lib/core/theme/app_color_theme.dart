import 'package:flutter/material.dart';

/// A pickable accent for the whole app, from settings' customisation
/// page (the "themes" tab, next to the launcher icon picker). Deliberately
/// narrow: background, surface, text and dividers stay the e-ink
/// cream/charcoal design in both light and dark mode ([AppColors.light]/
/// [AppColors.dark]) — only [AppColors.accent] swaps, everywhere it's
/// used (buttons, progress bars, active tabs, the memory/streaks
/// journals' own accent text). Each theme still needs its own light and
/// dark accent, for the same reason the e-ink theme's own forest/sage
/// pair does: a color dark enough to read on the light cream ground is
/// usually too dark to read on the charcoal one, so the dark variant is
/// a brighter version of the same hue, not the identical hex.
enum AppColorTheme {
  /// The app's own e-ink look, and the default every install starts on.
  forest(
    label: 'forest',
    lightAccent: Color(0xFF1E3F20),
    darkAccent: Color(0xFF5F9E65),
  ),

  /// The app's original "Mono & Teal" accent, from before the e-ink
  /// redesign — brought back as a pickable option rather than gone for
  /// good.
  blue(
    label: 'blue',
    lightAccent: Color(0xFF1A8FBF),
    darkAccent: Color(0xFF1B9FD9),
  ),

  red(
    label: 'red',
    lightAccent: Color(0xFF9C2F2F),
    darkAccent: Color(0xFFE2786F),
  ),
  purple(
    label: 'purple',
    lightAccent: Color(0xFF5B3E96),
    darkAccent: Color(0xFFB49BE8),
  ),
  teal(
    label: 'teal',
    lightAccent: Color(0xFF1B7A6E),
    darkAccent: Color(0xFF5FD9C4),
  ),
  pink(
    label: 'pink',
    lightAccent: Color(0xFF9C2A5C),
    darkAccent: Color(0xFFE285AE),
  ),
  amber(
    label: 'amber',
    lightAccent: Color(0xFF8A6206),
    darkAccent: Color(0xFFD9AE45),
  ),

  /// The one desaturated option — the e-ink look with its own accent
  /// dialled back to near-neutral, for a reader who wants no color
  /// standing out at all.
  graphite(
    label: 'graphite',
    lightAccent: Color(0xFF44403C),
    darkAccent: Color(0xFFC9C2B8),
  );

  const AppColorTheme({
    required this.label,
    required this.lightAccent,
    required this.darkAccent,
  });

  final String label;
  final Color lightAccent;
  final Color darkAccent;

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;
}
