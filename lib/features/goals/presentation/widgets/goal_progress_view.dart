import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/reading_goal.dart';

/// Progress towards the yearly goal — "7 of 24 books in 2026", a bar, and
/// whether that's ahead of or behind a steady pace.
///
/// [editable] controls whether tapping opens [onEdit] to change the goal —
/// the settings row is the one place that's true; everywhere else (the add
/// tab, the stats page) this is read-only, so there's exactly one place to
/// change a goal rather than three that can drift. With no goal set and
/// [editable] false this reads as a plain "no reading goal set yet" line
/// instead of a prompt, since tapping it wouldn't do anything.
///
/// [compact] is the add tab's version: one line and a thin bar, sized to sit
/// between the currently-reading row and the streak.
class GoalProgressView extends StatelessWidget {
  const GoalProgressView({
    super.key,
    required this.progress,
    this.onEdit,
    this.editable = true,
    this.compact = false,
    this.now,
  });

  /// Null when the reader has no goal.
  final ReadingGoal? progress;

  /// Required when [editable] is true; ignored otherwise.
  final VoidCallback? onEdit;

  /// Whether tapping this view opens [onEdit]. See the class doc comment.
  final bool editable;

  final bool compact;

  /// Test seam for the pace label.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = this.progress;

    if (progress == null) {
      if (!editable) {
        return Row(
          children: [
            Icon(Icons.flag_outlined, size: 16, color: colors.secondaryText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'no reading goal set yet',
                overflow: TextOverflow.ellipsis,
                style: context.fonts.interface(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        );
      }
      return Semantics(
        button: true,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 16, color: colors.accent),
                const SizedBox(width: 6),
                Text(
                  'set a reading goal',
                  style: context.fonts.interface(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pace = progress.paceLabel(now ?? DateTime.now());
    final percent = (progress.fraction * 100).round();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  progress.summary,
                  overflow: TextOverflow.ellipsis,
                  style: context.fonts.interface(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Text(
                pace,
                style: context.fonts.interface(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ],
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${progress.finished}',
                style: context.fonts.interface(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              Text(
                ' / ${progress.goal} books',
                style: context.fonts.interface(
                  fontSize: 16,
                  color: colors.secondaryText,
                ),
              ),
              if (editable) ...[
                const Spacer(),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: colors.secondaryText,
                ),
              ],
            ],
          ),
          Text(
            '${progress.year} goal · $pace',
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
        ],
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        _Bar(fraction: progress.fraction, thickness: compact ? 4 : 8),
      ],
    );

    if (!editable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: content,
      );
    }

    return Semantics(
      button: true,
      label:
          'Reading goal: ${progress.summary}, $percent percent, $pace. '
          'Double tap to change it.',
      excludeSemantics: true,
      onTap: onEdit,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: content,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.thickness});

  final double fraction;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Container(
      height: thickness,
      decoration: BoxDecoration(color: colors.divider, borderRadius: radius),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction,
        child: Container(
          decoration: BoxDecoration(color: colors.accent, borderRadius: radius),
        ),
      ),
    );
  }
}
