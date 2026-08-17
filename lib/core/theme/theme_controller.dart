import 'package:flutter/material.dart';

/// App-wide theme mode, swappable at runtime (e.g. via a debug toggle).
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(
    ThemeMode.system,
  );

  static void toggle() {
    mode.value = mode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }
}
