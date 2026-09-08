import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
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
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.title, this.center, this.trailing});

  /// The page's name, in the same style all four have always used.
  /// Null for a page whose header carries a [center] widget instead —
  /// the log tab, whose [DatePill] already names the day.
  final String? title;

  /// Optional widget centred in the row, independent of [title] — the
  /// log page's date pill, which was centred long before this header
  /// existed and stays that way.
  final Widget? center;

  /// Optional affordance sitting just inside the gear, e.g. a pro star
  /// shown only to readers who don't have it yet.
  final Widget? trailing;

  /// Both the row's height and the gear's tap target. 44 is the
  /// smallest square either platform's guidelines will call reachable.
  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = title;

    final row = Row(
      children: [
        if (label != null)
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          )
        else
          const Spacer(),
        ?trailing,
        if (trailing != null) const SizedBox(width: AppSpacing.sm),
        _SettingsButton(color: colors.secondaryText),
      ],
    );

    final centred = center;
    if (centred == null) return SizedBox(height: _tapTarget, child: row);

    // Stacked rather than slotted into the row, so the centred child is
    // centred on the *page* — the title and the gear can't pull it
    // off-axis by being different widths.
    return SizedBox(
      height: _tapTarget,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: centred),
          row,
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
      child: InkResponse(
        onTap: () => _open(context),
        radius: TopBar._tapTarget / 2,
        child: SizedBox(
          width: TopBar._tapTarget,
          height: TopBar._tapTarget,
          // Right-aligned inside its own tap target so the icon's right
          // edge lines up with the page's right padding, while the
          // target itself still spills out to a comfortable size around
          // it.
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(Icons.settings_outlined, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}
