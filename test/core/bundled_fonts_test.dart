import 'dart:io';

import 'package:book/core/theme/app_font_theme.dart';
import 'package:book/core/theme/bundled_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The bundled file `google_fonts` looks for, from the family it resolved a
/// request to — `JetBrainsMono_600italic` → `JetBrainsMono-SemiBoldItalic`.
String _fileFor(String resolvedFamily) {
  final at = resolvedFamily.lastIndexOf('_');
  final family = resolvedFamily.substring(0, at);
  final variant = resolvedFamily.substring(at + 1);
  final italic = variant.contains('italic');
  final digits = variant.replaceAll('italic', '').replaceAll('regular', '');
  final weight = digits.isEmpty ? 400 : int.parse(digits);
  const names = {
    100: 'Thin',
    200: 'ExtraLight',
    300: 'Light',
    400: 'Regular',
    500: 'Medium',
    600: 'SemiBold',
    700: 'Bold',
    800: 'ExtraBold',
    900: 'Black',
  };
  final part = names[weight]!;
  final name = part == 'Regular'
      ? (italic ? 'Italic' : 'Regular')
      : '$part${italic ? 'Italic' : ''}';
  return '$family-$name.ttf';
}

void main() {
  test('every family a font set uses is bundled', () {
    for (final theme in AppFontTheme.values) {
      for (final family in [
        theme.interfaceFamily,
        theme.bodyFamily,
        theme.bookTitleFamily,
      ]) {
        expect(BundledFonts.families, contains(family), reason: theme.label);
      }
    }
  });

  test(
    'every weight and style the app requests resolves to a bundled file',
    () {
      final missing = <String>[];
      for (final family in BundledFonts.families) {
        for (final (weight, style) in BundledFonts.requestedStyles) {
          final resolved = GoogleFonts.getFont(
            family,
            fontWeight: weight,
            fontStyle: style,
          ).fontFamily!;
          final file = _fileFor(resolved);
          if (!File('assets/google_fonts/$file').existsSync()) {
            missing.add('$family $weight $style → $file');
          }
        }
      }
      expect(missing, isEmpty);
    },
  );

  test('every bundled family ships its licence', () {
    final dir = Directory('assets/google_fonts');
    final fonts = {
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.ttf')) f.uri.pathSegments.last.split('-').first,
    };
    for (final family in fonts) {
      expect(
        File('assets/google_fonts/$family-LICENSE.txt').existsSync(),
        isTrue,
        reason: family,
      );
    }
  });
}
