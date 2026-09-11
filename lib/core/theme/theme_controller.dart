import 'package:flutter/material.dart';

/// App-wide theme mode, swappable at runtime from the appearance
/// section of settings.
///
/// Not persisted: [ThemeMode.system] is the default every launch, which
/// is the right default — a reader who has not chosen wants their
/// phone's choice. A reader who *has* chosen is choosing again next
/// launch, which is the one wart here and worth fixing if anyone
/// complains.
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Sets the mode outright — what the appearance control in settings
  /// uses, since it offers all three states rather than flipping
  /// between two.
  static void select(ThemeMode next) => mode.value = next;

  /// Flips between light and dark, ignoring [ThemeMode.system]. Kept
  /// for the debug row, where one tap to see the other theme beats
  /// three states to pick from.
  static void toggle() {
    mode.value = mode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }
}
