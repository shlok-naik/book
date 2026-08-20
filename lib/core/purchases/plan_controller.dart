import 'package:flutter/material.dart';

/// Debug-only override for whether the app should behave as if the
/// reader has "cactus pro" — independent of any real RevenueCat
/// entitlement — lets us eyeball both plan states without a real
/// purchase. Mirrors `ThemeController`.
class PlanController {
  PlanController._();

  static final ValueNotifier<bool> isPro = ValueNotifier(false);

  static void toggle() {
    isPro.value = !isPro.value;
  }
}
