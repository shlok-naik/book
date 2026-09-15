import 'package:book/core/platform/app_icon.dart';
import 'package:book/core/platform/app_icon_channel.dart';
import 'package:book/core/platform/app_icon_controller.dart';
import 'package:book/core/theme/app_color_theme.dart';
import 'package:book/core/theme/app_color_theme_controller.dart';
import 'package:book/core/theme/app_font_theme.dart';
import 'package:book/core/theme/app_font_theme_controller.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/settings/presentation/pages/customisation_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the icon grid asked for instead of touching
/// `UIApplication`/`PackageManager` — those only exist on a device.
class _FakeAppIconChannel extends AppIconChannel {
  _FakeAppIconChannel({AppIcon starting = AppIcon.originalLight})
    : _current = starting;

  AppIcon _current;
  final List<AppIcon> setCalls = [];

  /// Set to make the next [set] call fail, the way a reader dismissing
  /// iOS's own confirmation dialog would.
  bool failNext = false;

  @override
  Future<AppIcon> current() async => _current;

  @override
  Future<void> set(AppIcon icon) async {
    setCalls.add(icon);
    if (failNext) {
      failNext = false;
      throw StateError('the reader declined the icon change');
    }
    _current = icon;
  }
}

Future<void> pumpPage(WidgetTester tester, {ThemeData? theme}) async {
  // Tall enough that every group (including "themed", third and lowest)
  // is actually built — a plain ListView still only builds children
  // near the viewport, default-test-sized or not.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: const CustomisationPage(),
    ),
  );
  await tester.pump();
}

/// Runs [body] with `defaultTargetPlatform` forced to [platform], resetting
/// it before returning — inline, not via `addTearDown`, because Flutter's
/// own end-of-test invariant check (which asserts this is back to null)
/// runs before `addTearDown`/`tearDown` callbacks get a chance to.
Future<void> withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // AppIconController is a global — restore the real channel and its
  // default so a fake from one test can't leak into the next.
  setUp(() {
    addTearDown(() {
      AppIconController.channel = const AppIconChannel();
      AppIconController.current.value = AppIcon.originalLight;
      AppColorThemeController.current.value = AppColorTheme.forest;
      AppFontThemeController.current.value = AppFontTheme.original;
    });
  });

  // Flutter's test binding defaults `defaultTargetPlatform` to Android,
  // which would otherwise route every tap in this group through the
  // restart-confirmation sheet Android alone shows (see
  // CustomisationPage._select) — these tests are about the resolution
  // logic, not that sheet, so they force iOS instead. The dedicated
  // "on Android" group below covers the sheet itself.

  testWidgets('shows all three groups, each with its icons named', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.iOS, () async {
      await pumpPage(tester);

      expect(find.text('main'), findsOneWidget);
      expect(find.text('colours'), findsOneWidget);
      expect(find.text('themed'), findsOneWidget);

      // One tile per style, not a separate light/dark pair — see
      // CustomisationPage's `_IconChoice`.
      expect(find.text('original'), findsOneWidget);
      expect(find.text('booklines'), findsOneWidget);
      expect(find.text('lavender'), findsOneWidget);
      expect(find.text('sunflower'), findsOneWidget);
      expect(find.text('triangles'), findsOneWidget);
    });
  });

  testWidgets(
    'previews icons as rounded squares on iOS, round icons on Android',
    (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);
        expect(
          find.descendant(
            of: find.byType(ClipRRect),
            matching: find.byType(Image),
          ),
          findsWidgets,
        );
        expect(find.byType(ClipOval), findsNothing);
      });

      await withPlatform(TargetPlatform.android, () async {
        await pumpPage(tester);
        final paths = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => (image.image as AssetImage).assetName)
            .toList();
        expect(paths, isNotEmpty);
        expect(paths, everyElement(startsWith('assets/app_icons/round/')));
        expect(
          find.descendant(
            of: find.byType(ClipRRect),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
      });
    },
  );

  testWidgets('names the icon actually active, above the grid', (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      AppIconController.current.value = AppIcon.midnight;
      await pumpPage(tester);

      expect(find.text('currently'), findsOneWidget);
      // Once in the "currently" preview, once as the colours tile itself.
      expect(find.text('midnight'), findsNWidgets(2));
    });
  });

  testWidgets('picking a style in light mode applies its light icon', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.iOS, () async {
      // Started somewhere else, so picking "original" is a real change
      // rather than a no-op the current-icon guard skips.
      final channel = _FakeAppIconChannel(starting: AppIcon.midnight);
      AppIconController.channel = channel;
      AppIconController.current.value = AppIcon.midnight;
      await pumpPage(tester, theme: AppTheme.light);

      await tester.tap(find.text('original'));
      await tester.pumpAndSettle();

      expect(channel.setCalls, [AppIcon.originalLight]);
      expect(AppIconController.current.value, AppIcon.originalLight);
    });
  });

  testWidgets('picking the same style in dark mode applies its dark icon', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.iOS, () async {
      final channel = _FakeAppIconChannel();
      AppIconController.channel = channel;
      await pumpPage(tester, theme: AppTheme.dark);

      await tester.tap(find.text('original'));
      await tester.pumpAndSettle();

      expect(channel.setCalls, [AppIcon.originalDark]);
    });
  });

  testWidgets('a colour has no light/dark split either way', (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      final channel = _FakeAppIconChannel();
      AppIconController.channel = channel;
      await pumpPage(tester, theme: AppTheme.dark);

      await tester.tap(find.text('sunflower'));
      await tester.pumpAndSettle();

      expect(channel.setCalls, [AppIcon.sunflower]);
    });
  });

  testWidgets('a declined change leaves the icon as it was', (tester) async {
    await withPlatform(TargetPlatform.iOS, () async {
      final channel = _FakeAppIconChannel()..failNext = true;
      AppIconController.channel = channel;
      await pumpPage(tester);

      await tester.tap(find.text('sunflower'));
      await tester.pumpAndSettle();

      expect(AppIconController.current.value, AppIcon.originalLight);
    });
  });

  group('on Android', () {
    testWidgets('picking an icon asks to restart before applying it', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.android, () async {
        final channel = _FakeAppIconChannel();
        AppIconController.channel = channel;
        await pumpPage(tester);

        await tester.tap(find.text('sunflower'));
        await tester.pumpAndSettle();

        // Blocked on the sheet — nothing applied yet.
        expect(find.text('restart to apply'), findsOneWidget);
        expect(channel.setCalls, isEmpty);

        await tester.tap(find.text('apply and close cactus'));
        await tester.pumpAndSettle();

        expect(channel.setCalls, [AppIcon.sunflower]);
      });
    });

    testWidgets('backing out of the sheet applies nothing', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        final channel = _FakeAppIconChannel();
        AppIconController.channel = channel;
        await pumpPage(tester);

        await tester.tap(find.text('sunflower'));
        await tester.pumpAndSettle();
        // Dismiss the sheet without confirming, e.g. tapping the barrier.
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();

        expect(channel.setCalls, isEmpty);
        expect(AppIconController.current.value, AppIcon.originalLight);
      });
    });
  });

  group('themes tab', () {
    testWidgets('opens on icons by default, themes is the second tab', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);

        expect(find.text('icons'), findsOneWidget);
        expect(find.text('themes'), findsOneWidget);
        // Icons content is already on screen without switching tabs.
        expect(find.text('main'), findsOneWidget);
      });
    });

    testWidgets('switching to it names every theme, forest active first', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);

        await tester.tap(find.text('themes'));
        await tester.pumpAndSettle();

        expect(find.text('currently'), findsOneWidget);
        // Once in the "currently" preview, once as the tile itself.
        expect(find.text('forest'), findsNWidgets(2));
        for (final theme in AppColorTheme.values) {
          expect(find.text(theme.label), findsWidgets, reason: theme.label);
        }
        // A screen reader can pick one, not just find it.
        expect(
          tester.getSemantics(find.bySemanticsLabel('blue theme')),
          matchesSemantics(
            label: 'blue theme',
            isButton: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
      });
    });

    testWidgets('picking a theme applies it immediately, no confirmation', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);
        await tester.tap(find.text('themes'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('blue'));
        await tester.pumpAndSettle();

        expect(AppColorThemeController.current.value, AppColorTheme.blue);
        // Once in the "currently" preview, once as the tile itself.
        expect(find.text('blue'), findsNWidgets(2));
      });
    });
  });

  group('fonts tab', () {
    testWidgets('is the third tab, listing every font set with original '
        'active', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);
        expect(find.text('fonts'), findsOneWidget);

        await tester.tap(find.text('fonts'));
        await tester.pumpAndSettle();

        expect(find.text('currently'), findsOneWidget);
        // Once in the "currently" preview, once as the tile itself.
        expect(find.text('original'), findsNWidgets(2));
        for (final theme in AppFontTheme.values) {
          expect(
            find.byKey(ValueKey('font-${theme.name}')),
            findsOneWidget,
            reason: theme.label,
          );
        }
        expect(
          tester.getSemantics(find.byKey(const ValueKey('font-original'))),
          matchesSemantics(
            label: 'original fonts',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ),
        );
      });
    });

    testWidgets('each tile previews its own fonts, not the active ones', (
      tester,
    ) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);
        await tester.tap(find.text('fonts'));
        await tester.pumpAndSettle();

        final title = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('font-typewriter')),
            matching: find.text('Dune'),
          ),
        );
        expect(title.style!.fontFamily, startsWith('SpecialElite'));
      });
    });

    testWidgets('picking a font set applies it immediately', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpPage(tester);
        await tester.tap(find.text('fonts'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('font-book')));
        await tester.pumpAndSettle();

        expect(AppFontThemeController.current.value, AppFontTheme.book);
        expect(find.text('book'), findsNWidgets(2));
      });
    });
  });

  // Regression: TabBar calls onTap for the tab that's already selected, and
  // a no-op must not buzz.
  testWidgets('tapping the active tab gives no haptic; changing tab does', (
    tester,
  ) async {
    final vibrations = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          vibrations.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await withPlatform(TargetPlatform.iOS, () async {
      await pumpPage(tester);

      await tester.tap(find.text('icons'));
      await tester.pumpAndSettle();
      expect(vibrations, isEmpty);

      await tester.tap(find.text('themes'));
      await tester.pumpAndSettle();
      expect(vibrations, hasLength(1));
    });
  });
}
