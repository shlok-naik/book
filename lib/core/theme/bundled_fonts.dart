import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Every typeface the app draws with ships inside it, under
/// `assets/google_fonts/` — nothing is downloaded at runtime.
///
/// Downloading used to mean a first launch without a connection rendered in
/// fallback fonts, every new face (a font set picked in customisation) waited
/// on a download, and each of those requests told Google the reader's IP
/// address.
/// `google_fonts` finds a bundled file by its name (`<Family>-<Variant>.ttf`,
/// e.g. `JetBrainsMono-SemiBold.ttf`), so the files must keep those names.
///
/// **Adding a weight or style** the app doesn't use yet (see
/// [requestedStyles]) means bundling the variant it resolves to —
/// `test/core/bundled_fonts_test.dart` fails until the file is there.
abstract final class BundledFonts {
  /// The families bundled, by the `google_fonts` family name — every
  /// `AppFontTheme` role plus the fixed onboarding/paywall faces.
  static const families = [
    'JetBrains Mono',
    'Inter',
    'Fraunces',
    'EB Garamond',
    'Libre Baskerville',
    'Literata',
    'Libre Caslon Text',
    'Courier Prime',
    'Special Elite',
    'Share Tech Mono',
    'IBM Plex Mono',
    'Orbitron',
  ];

  /// Every weight and style any screen asks a family for: the app's own
  /// 400/600/700/800, Material's text theme 500, and the italics onboarding
  /// and the paywall use. Any font set can land in any role, so every
  /// family is bundled for all of them.
  static const requestedStyles = [
    (FontWeight.w400, FontStyle.normal),
    (FontWeight.w500, FontStyle.normal),
    (FontWeight.w600, FontStyle.normal),
    (FontWeight.w700, FontStyle.normal),
    (FontWeight.w800, FontStyle.normal),
    (FontWeight.w400, FontStyle.italic),
    (FontWeight.w600, FontStyle.italic),
    (FontWeight.w700, FontStyle.italic),
  ];

  /// Called once from `main`, before the first frame: turns off runtime
  /// fetching (a missing file is then a loud error in development rather
  /// than a silent download) and registers each font's licence for the
  /// licences page, as the SIL Open Font License and Apache 2.0 require.
  static void configure() {
    GoogleFonts.config.allowRuntimeFetching = false;
    LicenseRegistry.addLicense(() async* {
      for (final file in _licenceFiles) {
        final text = await rootBundle.loadString('assets/google_fonts/$file');
        final family = file.replaceAll('-LICENSE.txt', '');
        yield LicenseEntryWithLineBreaks(['google_fonts', family], text);
      }
    });
  }

  static const _licenceFiles = [
    'JetBrainsMono-LICENSE.txt',
    'Inter-LICENSE.txt',
    'Fraunces-LICENSE.txt',
    'EBGaramond-LICENSE.txt',
    'LibreBaskerville-LICENSE.txt',
    'Literata-LICENSE.txt',
    'LibreCaslonText-LICENSE.txt',
    'CourierPrime-LICENSE.txt',
    'SpecialElite-LICENSE.txt',
    'ShareTechMono-LICENSE.txt',
    'IBMPlexMono-LICENSE.txt',
    'Orbitron-LICENSE.txt',
  ];
}
