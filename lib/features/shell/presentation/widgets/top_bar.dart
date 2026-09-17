import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/offline_indicator.dart';
import '../../../settings/presentation/pages/settings_page.dart';

/// The header every top-level page wears: the page's own name on the
/// left, an optional [trailing] affordance, and the settings gear in the
/// top right corner.
///
/// There is one definition rather than four hand-rolled headers because
/// the gear is the app's only route to settings — a reader who cannot
/// find it on the page they happen to be on cannot find it at all, so
/// its position is identical on all four tabs, down to the pixel.
///
/// The title sits flush against the page's own left padding, exactly
/// where each page's heading sat before there was a gear at all: putting
/// the gear on the right keeps it out of the reading order and lets the
/// headings line up with the content beneath them again. The icon's
/// *right* edge lands on the page's right padding for the same reason.
///
/// Pages keep their own horizontal padding; this adds none.
///
/// Left of the gear sits [OfflineIndicator] — nothing while online, a
/// crossed-out cloud while the app is working offline.
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.trailing});

  /// The page's name, in the same style all four have always used.
  final String title;

  /// Optional affordance sitting just inside the gear, e.g. a pro star
  /// shown only to readers who don't have it yet.
  final Widget? trailing;

  /// Both the row's height and the gear's tap target. 44 is the
  /// smallest square either platform's guidelines will call reachable.
  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // A minimum, not a fixed height: at a large text size the title grows
    // the bar rather than being clipped by it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _tapTarget),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: context.fonts.interface(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ),
          ?trailing,
          if (trailing != null) const SizedBox(width: AppSpacing.sm),
          // Just left of the gear, on every tab; takes no room at all
          // while online — see [OfflineIndicator].
          const OfflineIndicator(),
          _SettingsButton(color: colors.secondaryText),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.color});

  final Color color;

  void _open(BuildContext context) {
    AppHaptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Named so the screen shows up in the analytics funnel — see
        // [AppAnalytics.navigatorObservers].
        settings: const RouteSettings(name: 'settings'),
        builder: (_) => const SettingsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Settings',
      excludeSemantics: true,
      child: SizedBox(
        width: TopBar._tapTarget,
        height: TopBar._tapTarget,
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            // The full 44x44 square stays reachable — an InkResponse
            // sized to just the icon (below) would only register taps
            // inside its own small bounds.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(context),
              ),
            ),
            // Sized to the icon itself, not the tap target around it,
            // so the ripple/highlight InkResponse centers on the icon
            // it's drawn over — an InkResponse spanning the full 44x44
            // target instead centers its ink there, well to the left of
            // an icon that's right-aligned inside it.
            InkResponse(
              onTap: () => _open(context),
              radius: TopBar._tapTarget / 2,
              child: Icon(Icons.settings_outlined, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
