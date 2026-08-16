import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Shown in place of the text field right after a recognized command is
/// submitted — draws a strikethrough across what was typed, then pops in
/// a checkmark, before the field resets for the next entry.
class CompletedCommand extends StatelessWidget {
  const CompletedCommand({
    super.key,
    required this.text,
    required this.animation,
    required this.style,
  });

  final String text;
  final Animation<double> animation;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strike = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    final checkmark = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.5, 1, curve: Curves.elasticOut),
    );
    // Matches the text's own rendered line height, so a same-height,
    // same-top-aligned box lets the checkmark center itself against the
    // text/strikethrough specifically — not the row's full height.
    final lineHeight = style.fontSize! * (style.height ?? 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Painted first (behind the text) so the line only shows
                  // through the gaps between letters, the way strikethrough
                  // conventionally renders — painted on top, it erases
                  // chunks of the glyph strokes and reads as "cut into".
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: strike.value.clamp(0.0, 1.0),
                        child: Container(height: 2, color: colors.accent),
                      ),
                    ),
                  ),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Same dark color as the TextField it replaces — a
                    // lighter gray here measurably read as "smaller" even
                    // at an identical font size (a contrast illusion).
                    style: style.copyWith(color: colors.primaryText),
                  ),
                ],
              ),
            ),
            // Reserved from the very first frame (not conditionally added)
            // so the Flexible text area's width — and the text's position
            // — never shifts once the checkmark starts appearing.
            const SizedBox(width: 10),
            SizedBox(
              height: lineHeight,
              child: Center(
                child: Transform.scale(
                  scale: checkmark.value,
                  child: Icon(Icons.check_circle, color: colors.accent, size: 22),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
