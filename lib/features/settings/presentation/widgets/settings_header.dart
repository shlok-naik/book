import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/widgets/offline_indicator.dart';

/// The heading a page pushed *from* settings wears: [title] flush left
/// at the exact same position [TopBar]'s own title sits at on every
/// top-level page, then a back chevron in the same top-right slot the
/// gear occupies everywhere else — this is a screen a reader leaves
/// *back* from rather than opens *into*.
///
/// Deliberately not an [AppBar]. Nothing else in this app has one, and
/// its Material defaults — the surface tint, the elevation shadow on
/// scroll, the centred title — would make a settings screen look like
/// it came from a different app than the four a reader uses daily. The
/// geometry matches `TopBar` exactly — title first, icon last, both in
/// the same 44pt row — so a pushed page's own name lands pixel-for-
/// pixel where "library"/"streak"/"memory"/"add" do, not shifted right
/// by a leading icon the way a naive "back, then title" row would.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key, required this.title});

  final String title;

  /// The same 44pt square `TopBar` gives its gear.
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
          // The same offline mark `TopBar` shows left of its gear, so it's
          // on settings and every page pushed from it too.
          const OfflineIndicator(),
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: SizedBox(
              width: _tapTarget,
              height: _tapTarget,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  // The full 44x44 square stays reachable — an
                  // InkResponse sized to just the icon (below) would
                  // only register taps inside its own small bounds.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: Navigator.of(context).pop,
                    ),
                  ),
                  // Sized to the icon itself, not the tap target around
                  // it, so the ripple/highlight InkResponse centers on
                  // the icon it's drawn over — an InkResponse spanning
                  // the full 44x44 target instead centers its ink
                  // there, well to the left of an icon that's
                  // right-aligned inside it, exactly where `TopBar`'s
                  // own gear sits on every other page.
                  InkResponse(
                    onTap: Navigator.of(context).pop,
                    radius: _tapTarget / 2,
                    child: Icon(
                      Icons.chevron_left,
                      size: 24,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
