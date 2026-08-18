import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'marquee_row.dart';

/// A tilted stack of auto-scrolling [MarqueeRow]s — the tutorial step's
/// "command wall" look, generalised so any screen can wear it.
///
/// Extracted from `CommandWall` when the paywall needed the same
/// treatment for its feature pills: rather than re-deriving the row
/// cadence (and drifting out of sync with it later), both screens now
/// pass their own chips into this one widget and inherit identical
/// behaviour — the tilt, the per-row speeds, and the alternating
/// directions that keep neighbouring rows from marching in lockstep.
///
/// Rows cycle through [_durations] and alternate direction by index, so
/// a three-row wall reads 18s forward / 14s back / 20s forward — the
/// exact cadence the tutorial page shipped with.
class TiltedMarqueeWall extends StatelessWidget {
  const TiltedMarqueeWall({
    super.key,
    required this.rows,
    this.rowHeight = 40,
    this.rowSpacing = AppSpacing.sm,
    this.tiltDegrees = -6,
  });

  /// One list of chips per row. Each row scrolls independently.
  final List<List<Widget>> rows;

  final double rowHeight;
  final double rowSpacing;

  /// Negative tilts the wall up to the right, matching the tutorial.
  final double tiltDegrees;

  static const _durations = [
    Duration(seconds: 18),
    Duration(seconds: 14),
    Duration(seconds: 20),
  ];

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDegrees * pi / 180,
      // Clipped to the *unrotated* bounds so the tilted rows are cut off
      // in a tidy rectangle instead of poking into whatever sits above
      // and below them.
      child: ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: rowSpacing),
              MarqueeRow(
                duration: _durations[i % _durations.length],
                reverse: i.isOdd,
                height: rowHeight,
                children: rows[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
