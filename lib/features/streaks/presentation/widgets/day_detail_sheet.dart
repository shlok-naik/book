import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';

/// Opened from tapping a day-dot on the streaks grid — a standard modal
/// bottom sheet: full width, rounded top corners only, a drag handle,
/// sliding up from the bottom edge. Swipe down or tap outside to dismiss.
Future<void> showDayDetailSheet(BuildContext context, DateTime date) {
  final colors = context.colors;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.background,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    constraints: const BoxConstraints(maxWidth: double.infinity),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) {
      final minHeight = MediaQuery.sizeOf(context).height * 0.32;

      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DatePill(date: date),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
