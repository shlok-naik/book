import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/platform/app_icon.dart';
import '../../../../core/platform/app_icon_controller.dart';
import '../../../../core/theme/app_color_theme.dart';
import '../../../../core/theme/app_color_theme_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/settings_header.dart';

/// One pickable entry in the grid. Most styles have a light and a dark
/// rendering — [resolve] is what picks between them, by the app's
/// *current* brightness rather than offering both as separate tiles:
/// a reader picks "sunset", not "sunset · light" versus "sunset · dark".
/// [dark] is null for the "colours" group, where the color itself is
/// the choice and there is nothing to resolve.
class _IconChoice {
  const _IconChoice({required this.label, required this.light, this.dark});

  final String label;
  final AppIcon light;
  final AppIcon? dark;

  AppIcon resolve(Brightness brightness) =>
      (brightness == Brightness.dark ? dark : null) ?? light;
}

const _mainChoices = [
  _IconChoice(
    label: 'original',
    light: AppIcon.originalLight,
    dark: AppIcon.originalDark,
  ),
  _IconChoice(
    label: 'booklines',
    light: AppIcon.booklinesLight,
    dark: AppIcon.booklinesDark,
  ),
];

const _coloursChoices = [
  _IconChoice(label: 'lavender', light: AppIcon.lavender),
  _IconChoice(label: 'midnight', light: AppIcon.midnight),
  _IconChoice(label: 'mint', light: AppIcon.mint),
  _IconChoice(label: 'raspberry', light: AppIcon.raspberry),
  _IconChoice(label: 'rose', light: AppIcon.rose),
  _IconChoice(label: 'sunflower', light: AppIcon.sunflower),
];

const _themedChoices = [
  _IconChoice(
    label: 'clouds',
    light: AppIcon.cloudsLight,
    dark: AppIcon.cloudsDark,
  ),
  _IconChoice(
    label: 'sunset',
    light: AppIcon.sunsetLight,
    dark: AppIcon.sunsetDark,
  ),
  _IconChoice(
    label: 'triangles',
    light: AppIcon.trianglesLight,
    dark: AppIcon.trianglesDark,
  ),
];

const _groups = <AppIconGroup, List<_IconChoice>>{
  AppIconGroup.main: _mainChoices,
  AppIconGroup.colours: _coloursChoices,
  AppIconGroup.themed: _themedChoices,
};

/// Every launcher icon, grouped as main / colours / themed — reached
/// from `SettingsPage`'s "customisation" row, pro-only. Dressed like
/// `LibraryPage`/`MemoryPage` rather than a Material picker sheet, since
/// it is one level under a tab rather than a dialog: the same
/// `Scaffold` + `SafeArea` + `AppSpacing.xl` gutter, and [SettingsHeader]
/// for the same reason `SettingsPage` itself uses it.
///
/// Each group's label is the exact face, size and color the streak
/// journal's date label and the memory journal's book name already
/// use — a group name is this page's "day"/"book".
///
/// Picking a style applies it immediately rather than marking a
/// selection to confirm — the "which one is active" question is
/// answered by the preview at the top of the page, not by a ring drawn
/// on a tile in the grid below.
class CustomisationPage extends StatefulWidget {
  const CustomisationPage({super.key});

  @override
  State<CustomisationPage> createState() => _CustomisationPageState();
}

class _CustomisationPageState extends State<CustomisationPage> {
  bool _busy = false;

  Future<void> _select(AppIcon icon) async {
    if (_busy || AppIconController.current.value == icon) return;

    // Android's activity-alias switch does take effect immediately, but
    // the already-running task can go on showing the old icon in
    // Recents until the app is reopened — so a reader needs telling,
    // where iOS needs nothing extra: `setAlternateIconName` raises the
    // system's own confirmation and applies instantly.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final confirmed = await _showRestartSheet(context);
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      await AppIconController.select(icon);
      AppHaptics.accepted();
    } on Object {
      // The reader dismissed iOS's own confirmation dialog, or the
      // platform call otherwise failed — either way nothing changed, so
      // this is the same "it didn't happen" the rest of the app reaches
      // for, not an error banner.
      AppHaptics.rejected();
      if (mounted) setState(() => _busy = false);
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      SystemNavigator.pop();
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  Widget _iconsTab(Brightness brightness) {
    return ValueListenableBuilder<AppIcon>(
      valueListenable: AppIconController.current,
      builder: (context, current, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            _CurrentIcon(icon: current),
            const SizedBox(height: AppSpacing.lg),
            for (final (i, entry) in _groups.entries.indexed) ...[
              // Same gap as _IconGroup puts between its own label and
              // its icons, so a group's icons sit as far from the label
              // above ("main") as from the next group's label below
              // ("colours") — not the label-hugs-content,
              // section-break-is-bigger split this used to have.
              if (i > 0) const SizedBox(height: AppSpacing.md),
              _IconGroup(
                group: entry.key,
                choices: entry.value,
                brightness: brightness,
                busy: _busy,
                onSelect: _select,
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;
    final labelStyle = GoogleFonts.jetBrainsMono(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          // Icons first — the tab this page has always opened on, so a
          // reader who's been here before lands exactly where they left
          // off; themes is the new second tab, not a replacement.
          child: DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsHeader(title: 'customisation'),
                const SizedBox(height: AppSpacing.sm),
                // Same tab bar the library's "+" panel uses for
                // shelves/tags/series — same colors, same face.
                TabBar(
                  labelColor: colors.accent,
                  unselectedLabelColor: colors.secondaryText,
                  indicatorColor: colors.accent,
                  dividerColor: colors.divider,
                  labelStyle: labelStyle,
                  unselectedLabelStyle: labelStyle.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  onTap: (_) => AppHaptics.selection(),
                  tabs: const [
                    Tab(
                      key: ValueKey('customisation-tab-icons'),
                      text: 'icons',
                    ),
                    Tab(
                      key: ValueKey('customisation-tab-themes'),
                      text: 'themes',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: TabBarView(
                    children: [_iconsTab(brightness), _ThemesTab(brightness)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet confirming the reader wants to switch — Android needs the app
/// to close and reopen for its home screen icon to visibly update.
/// Returns true if they confirmed, null/false if they backed out.
Future<bool?> _showRestartSheet(BuildContext context) {
  final colors = context.colors;

  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'restart to apply',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'cactus needs to close and reopen for the new icon to show '
            'on your home screen.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: 'apply and close cactus',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    ),
  );
}

/// An icon preview shaped the way the home screen will show it: the
/// pre-cut circle on Android (the Pixel launcher's default adaptive-icon
/// shape), the square art in iOS's rounded square everywhere else.
class _IconImage extends StatelessWidget {
  const _IconImage({required this.icon, required this.size});

  final AppIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS's icon corner radius is ~22.37% of the icon's side.
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2237),
        child: Image.asset(
          icon.assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Image.asset(
      icon.roundAssetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
  }
}

/// The icon actually active right now — shown once, above the grid,
/// rather than as a ring drawn on whichever tile matches it below.
class _CurrentIcon extends StatelessWidget {
  const _CurrentIcon({required this.icon});

  final AppIcon icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        _IconImage(icon: icon, size: 56),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'currently',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              icon.label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One labelled group of icon tiles, four to a row — see
/// [CustomisationPage] for why the label matches the streak/memory
/// journals' own group labels.
class _IconGroup extends StatelessWidget {
  const _IconGroup({
    required this.group,
    required this.choices,
    required this.brightness,
    required this.busy,
    required this.onSelect,
  });

  final AppIconGroup group;
  final List<_IconChoice> choices;
  final Brightness brightness;
  final bool busy;
  final ValueChanged<AppIcon> onSelect;

  static const _crossAxisCount = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same face, size and color the streak journal's date label and
        // the memory journal's book name use.
        Text(
          group.label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // A Wrap, not a GridView — each row's height comes from its own
        // tile's real content (icon + caption), not a guessed number or
        // a width-derived aspect ratio. A `childAspectRatio` grid cell
        // is exactly as tall as it is wide (times a ratio), which has
        // nothing to do with how tall an icon-plus-caption actually is;
        // on a wide screen that leaves slack below the caption that
        // GridView still counts as part of the grid, so the gap from
        // the *icons* down to the next group's label ends up bigger
        // than the gap from *this* label down to the icons above —
        // even though both use the same SizedBox height.
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth =
                (constraints.maxWidth - AppSpacing.sm * (_crossAxisCount - 1)) /
                _crossAxisCount;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.md,
              children: [
                for (final choice in choices)
                  SizedBox(
                    width: tileWidth,
                    child: _IconTile(
                      label: choice.label,
                      icon: choice.resolve(brightness),
                      onTap: busy
                          ? null
                          : () => onSelect(choice.resolve(brightness)),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One icon's thumbnail and its name underneath. Tapping plays a quick
/// grow-then-settle so a reader sees their tap land before the restart
/// sheet appears — there is no lasting "selected" mark here; that lives
/// in [_CurrentIcon] instead.
class _IconTile extends StatefulWidget {
  const _IconTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;

  /// Already resolved for the current brightness, so a reader in dark
  /// mode sees the dark rendering of "sunset" without picking a mode.
  final AppIcon icon;
  final VoidCallback? onTap;

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _pressed = false;

  static const _size = 56.0;

  Future<void> _handleTap() async {
    final onTap = widget.onTap;
    if (onTap == null) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (mounted) setState(() => _pressed = false);
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: widget.onTap == null ? null : _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _pressed ? 1.18 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: _IconImage(icon: widget.icon, size: _size),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "themes" tab: an accent color for the whole app — background,
/// surface and text stay the e-ink cream/charcoal look in both light and
/// dark mode; only the accent (buttons, progress bars, active states,
/// the "currently reading" ring…) changes. Laid out exactly like the
/// icons tab: a "currently" preview above a wrapped grid of tiles, and
/// picking one applies immediately rather than needing a confirm.
class _ThemesTab extends StatelessWidget {
  const _ThemesTab(this.brightness);

  final Brightness brightness;

  static const _crossAxisCount = 4;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppColorTheme>(
      valueListenable: AppColorThemeController.current,
      builder: (context, current, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            _CurrentTheme(theme: current, brightness: brightness),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth =
                    (constraints.maxWidth -
                        AppSpacing.sm * (_crossAxisCount - 1)) /
                    _crossAxisCount;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final theme in AppColorTheme.values)
                      SizedBox(
                        width: tileWidth,
                        child: _ThemeTile(
                          theme: theme,
                          brightness: brightness,
                          selected: theme == current,
                          onTap: () {
                            if (theme == current) return;
                            AppHaptics.selection();
                            unawaited(AppColorThemeController.select(theme));
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// The color theme actually active right now — shown once, above the
/// grid, the same way [_CurrentIcon] names the active launcher icon.
class _CurrentTheme extends StatelessWidget {
  const _CurrentTheme({required this.theme, required this.brightness});

  final AppColorTheme theme;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.resolve(brightness),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'currently',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              theme.label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One theme's swatch and its name underneath — a filled circle in the
/// theme's own accent (resolved for the current brightness, the same
/// way an icon's light/dark rendering is), checked when it's the one
/// active right now.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final AppColorTheme theme;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final swatch = theme.resolve(brightness);

    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} theme',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: colors.primaryText, width: 2)
                    : null,
              ),
              child: selected
                  ? Center(
                      child: Icon(
                        Icons.check,
                        color: colors.background,
                        size: 22,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              theme.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
