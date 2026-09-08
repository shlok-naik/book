import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A labelled group of settings rows: a small caption, then the rows
/// stacked on one shared surface with hairlines between them.
///
/// Grouping is what makes a settings list readable — an undifferentiated
/// column of twelve rows reads as a wall, the same twelve in four named
/// groups reads as four decisions.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            title,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSpacing.md,
                    color: colors.divider,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row in a [SettingsSection]: an icon, a label, an optional
/// [value] read out on the right, and either a chevron (it opens
/// something) or a [trailing] control (it *is* the control).
///
/// A null [onTap] with no [trailing] renders an inert row — used for
/// facts rather than actions, like the email address a reader has
/// already linked.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final readout = value;
    final control = trailing;
    final enabled = onTap != null;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.secondaryText),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ),
          if (readout != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                readout,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colors.secondaryText,
                ),
              ),
            ),
          if (control != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: control,
            )
          else if (enabled)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: colors.secondaryText,
              ),
            ),
        ],
      ),
    );

    // Rows that do nothing get no ink and no button semantics — a
    // screen reader announcing "email, button" for a read-only address
    // is a lie a sighted reader is never told.
    if (!enabled) return content;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
