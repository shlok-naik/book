import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

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

    return SizedBox(
      height: _tapTarget,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: InkResponse(
              onTap: Navigator.of(context).pop,
              radius: _tapTarget / 2,
              child: SizedBox(
                width: _tapTarget,
                height: _tapTarget,
                // Right-aligned inside the target, exactly where
                // `TopBar`'s own gear sits on every other page.
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.chevron_left,
                    size: 24,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
