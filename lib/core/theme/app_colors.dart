import 'package:flutter/material.dart';

/// Mono & Teal design system colors, exposed as a [ThemeExtension] so
/// widgets never hardcode hex values directly.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.divider,
    required this.loggedMark,
  });

  final Color background;
  final Color surface;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color divider;

  /// Vivid blue used only for the streaks grid's logged-day marks — a
  /// day with nothing logged draws in [primaryText] instead. Deliberately
  /// distinct from [accent]'s teal so a glance at the grid separates
  /// "something happened" from the rest of the app's chrome.
  final Color loggedMark;

  static const light = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F5),
    primaryText: Color(0xFF000000),
    secondaryText: Color(0xFF6B6B6B),
    accent: Color(0xFF1A8FBF),
    divider: Color(0xFFE8E8E8),
    loggedMark: Color(0xFF2F6FED),
  );

  static const dark = AppColors(
    background: Color(0xFF1A1A1A),
    surface: Color(0xFF242424),
    primaryText: Color(0xFFF5F5F5),
    secondaryText: Color(0xFF9A9A9A),
    accent: Color(0xFF1B9FD9),
    divider: Color(0xFF3A3A3A),
    loggedMark: Color(0xFF2F6FED),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
    Color? divider,
    Color? loggedMark,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      accent: accent ?? this.accent,
      divider: divider ?? this.divider,
      loggedMark: loggedMark ?? this.loggedMark,
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
      divider: Color.lerp(divider, other.divider, t)!,
      loggedMark: Color.lerp(loggedMark, other.loggedMark, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
