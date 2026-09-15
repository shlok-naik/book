import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A labelled group on the book info and editions pages: a small caption,
/// then its rows on one shared surface with hairlines between them.
///
/// The same look as settings' `SettingsSection` — same caption face, same
/// surface, same radius, same hairline — so a pushed page from the library
/// reads as the same app. It exists separately only because these pages
/// need two things that one doesn't have: the caption is announced as a
/// *heading* (so a screen-reader user can jump section to section on a long
/// page), and it's optional, for a lone row that needs no caption.
class InfoSection extends StatelessWidget {
  const InfoSection({super.key, this.title, required this.rows});

  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                caption,
                style: context.fonts.interface(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: ClipRRect(
            // Clipped so a row's ink ripple stays inside the rounded card.
            borderRadius: BorderRadius.circular(AppRadius.md),
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
        ),
      ],
    );
  }
}

/// Google Books' date strings as a reader would write them: "2005" stays
/// "2005", "2005-08" becomes "Aug 2005", "2005-08-02" becomes "2 Aug 2005".
/// Anything else (Google occasionally sends "c. 1965") is shown verbatim
/// rather than guessed at.
String formatPublishedDate(String raw) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final match = RegExp(
    r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$',
  ).firstMatch(raw.trim());
  if (match == null) return raw.trim();
  final year = match.group(1)!;
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (month == null || month < 1 || month > 12) return year;
  final monthName = months[month - 1];
  if (day == null || day < 1 || day > 31) return '$monthName $year';
  return '$day $monthName $year';
}
