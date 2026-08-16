import 'package:flutter/material.dart';

/// Disables the platform overscroll indicator (Android's stretch effect,
/// iOS/Android's glow) app-wide — nothing here needs the extra motion.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
