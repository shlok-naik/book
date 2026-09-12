/// Which launcher icon is active — sixteen icons across three groups.
/// Kept separate from [ThemeMode] deliberately: the reader picks this
/// independently of light/dark mode, the same way the "pick a look"
/// onboarding screen sets [ThemeController] without gating it on
/// anything else.
///
/// [originalLight] is the app's actual bundle icon on both platforms —
/// the one baked into `AppIcon.appiconset` on iOS and `ic_launcher` on
/// Android — every other value is an alternate/alias. Keep this in step
/// with `AppDelegate.swift`'s `alternateIconNames` and
/// `MainActivity.kt`'s `componentSuffixes`.
enum AppIcon {
  // main — the original glyph, plus a book-lines texture behind it.
  originalLight,
  originalDark,
  booklinesLight,
  booklinesDark,

  // colours — one flat color each; the color itself is the choice, so
  // there is no light/dark split.
  lavender,
  midnight,
  mint,
  raspberry,
  rose,
  sunflower,

  // themed — a small illustrated scene behind the glyph.
  cloudsLight,
  cloudsDark,
  sunsetLight,
  sunsetDark,
  trianglesLight,
  trianglesDark,
}

/// The three groups [AppIcon] values fall into — how the customisation
/// page's three labelled sections are built.
enum AppIconGroup { main, colours, themed }

extension AppIconNaming on AppIcon {
  AppIconGroup get group => switch (this) {
    AppIcon.originalLight ||
    AppIcon.originalDark ||
    AppIcon.booklinesLight ||
    AppIcon.booklinesDark => AppIconGroup.main,
    AppIcon.lavender ||
    AppIcon.midnight ||
    AppIcon.mint ||
    AppIcon.raspberry ||
    AppIcon.rose ||
    AppIcon.sunflower => AppIconGroup.colours,
    AppIcon.cloudsLight ||
    AppIcon.cloudsDark ||
    AppIcon.sunsetLight ||
    AppIcon.sunsetDark ||
    AppIcon.trianglesLight ||
    AppIcon.trianglesDark => AppIconGroup.themed,
  };

  /// The name under its thumbnail on the customisation page.
  String get label => switch (this) {
    AppIcon.originalLight => 'original · light',
    AppIcon.originalDark => 'original · dark',
    AppIcon.booklinesLight => 'booklines · light',
    AppIcon.booklinesDark => 'booklines · dark',
    AppIcon.lavender => 'lavender',
    AppIcon.midnight => 'midnight',
    AppIcon.mint => 'mint',
    AppIcon.raspberry => 'raspberry',
    AppIcon.rose => 'rose',
    AppIcon.sunflower => 'sunflower',
    AppIcon.cloudsLight => 'clouds · light',
    AppIcon.cloudsDark => 'clouds · dark',
    AppIcon.sunsetLight => 'sunset · light',
    AppIcon.sunsetDark => 'sunset · dark',
    AppIcon.trianglesLight => 'triangles · light',
    AppIcon.trianglesDark => 'triangles · dark',
  };

  /// The wire value the platform channel sends and expects back —
  /// snake_case, matching `AppDelegate.swift` and `MainActivity.kt`.
  String get wireName => switch (this) {
    AppIcon.originalLight => 'original_light',
    AppIcon.originalDark => 'original_dark',
    AppIcon.booklinesLight => 'booklines_light',
    AppIcon.booklinesDark => 'booklines_dark',
    AppIcon.lavender => 'lavender',
    AppIcon.midnight => 'midnight',
    AppIcon.mint => 'mint',
    AppIcon.raspberry => 'raspberry',
    AppIcon.rose => 'rose',
    AppIcon.sunflower => 'sunflower',
    AppIcon.cloudsLight => 'clouds_light',
    AppIcon.cloudsDark => 'clouds_dark',
    AppIcon.sunsetLight => 'sunset_light',
    AppIcon.sunsetDark => 'sunset_dark',
    AppIcon.trianglesLight => 'triangles_light',
    AppIcon.trianglesDark => 'triangles_dark',
  };

  /// The bundled thumbnail the customisation page renders — same art as
  /// the native icon, declared under `assets/app_icons/` in
  /// pubspec.yaml.
  String get assetPath => 'assets/app_icons/$wireName.png';

  static AppIcon fromWireName(String? name) => AppIcon.values.firstWhere(
    (icon) => icon.wireName == name,
    orElse: () => AppIcon.originalLight,
  );
}

extension AppIconGroupNaming on AppIconGroup {
  String get label => switch (this) {
    AppIconGroup.main => 'main',
    AppIconGroup.colours => 'colours',
    AppIconGroup.themed => 'themed',
  };
}
