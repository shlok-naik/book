import 'package:flutter/material.dart';

/// Parchment & Cobalt design system colors, exposed as a [ThemeExtension]
/// so widgets never hardcode hex values directly.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
  });

  final Color background;
  final Color surface;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;

  /// The app's single accent color — every button, highlight, pill, and
  /// dot reads from here (light and dark alike). Change this one line to
  /// reskin the whole app.
  static const mainColor = Color(0xFFE8720F);

  static const light = AppColors(
    background: Color(0xFFFAF7F2),
    surface: Color(0xFFF3EEE6),
    primaryText: Color(0xFF1A1C20),
    secondaryText: Color(0xFF6E737D),
    accent: mainColor,
  );

  static const dark = AppColors(
    background: Color(0xFF16233E),
    surface: Color(0xFF1E2B49),
    primaryText: Color(0xFFF9F9F6),
    secondaryText: Color(0xFF8B94A3),
    accent: mainColor,
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      accent: accent ?? this.accent,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
