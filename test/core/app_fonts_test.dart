import 'package:book/core/theme/app_color_theme.dart';
import 'package:book/core/theme/app_font_theme.dart';
import 'package:book/core/theme/app_font_theme_controller.dart';
import 'package:book/core/theme/app_fonts.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/shell/presentation/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => AppFontThemeController.current.value = AppFontTheme.original);

  group('AppFonts', () {
    test('original sets type exactly as the app always has', () {
      const fonts = AppFonts.original;
      expect(
        fonts.interface(fontWeight: FontWeight.w600).fontFamily,
        GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w600).fontFamily,
      );
      expect(fonts.body().fontFamily, GoogleFonts.inter().fontFamily);
      expect(fonts.bookTitle().fontFamily, GoogleFonts.fraunces().fontFamily);
    });

    test('every font set names families Google Fonts actually has', () {
      for (final theme in AppFontTheme.values) {
        final fonts = AppFonts(theme);
        // getFont throws for an unknown family name.
        expect(fonts.interface, returnsNormally, reason: theme.label);
        expect(fonts.body, returnsNormally, reason: theme.label);
        expect(fonts.bookTitle, returnsNormally, reason: theme.label);
      }
    });

    test('the app theme carries the chosen set; the default is original', () {
      expect(AppTheme.light.extension<AppFonts>(), AppFonts.original);
      expect(
        AppTheme.darkWith(
          AppColorTheme.forest,
          AppFontTheme.robotic,
        ).extension<AppFonts>(),
        const AppFonts(AppFontTheme.robotic),
      );
    });

    testWidgets('a change reaches a page already on screen', (tester) async {
      await tester.pumpWidget(
        ValueListenableBuilder<AppFontTheme>(
          valueListenable: AppFontThemeController.current,
          builder: (context, fontTheme, _) => MaterialApp(
            theme: AppTheme.lightWith(AppColorTheme.forest, fontTheme),
            home: const Scaffold(body: TopBar(title: 'library')),
          ),
        ),
      );
      String? titleFamily() =>
          tester.widget<Text>(find.text('library')).style?.fontFamily;
      expect(titleFamily(), startsWith('JetBrainsMono'));

      AppFontThemeController.current.value = AppFontTheme.robotic;
      // MaterialApp animates between themes.
      await tester.pumpAndSettle();

      expect(titleFamily(), startsWith('ShareTechMono'));
    });
  });

  group('AppFontThemeController', () {
    test('reads back a saved choice', () async {
      SharedPreferences.setMockInitialValues({'app_theme.font': 'classic'});
      await AppFontThemeController.initialize();
      expect(AppFontThemeController.current.value, AppFontTheme.classic);
    });

    test('an unknown saved value leaves the original', () async {
      SharedPreferences.setMockInitialValues({'app_theme.font': 'comic-sans'});
      await AppFontThemeController.initialize();
      expect(AppFontThemeController.current.value, AppFontTheme.original);
    });

    test('saves what was picked', () async {
      SharedPreferences.setMockInitialValues({});
      await AppFontThemeController.select(AppFontTheme.typewriter);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme.font'), 'typewriter');
    });
  });
}
