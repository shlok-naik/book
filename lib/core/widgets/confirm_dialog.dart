import 'package:flutter/material.dart';

import '../../features/paywall/presentation/widgets/soft_pill_button.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Asks "are you sure?" before something that can't be undone — deleting
/// a book, replacing a library on import, discarding a library when two
/// devices are linked to one email.
///
/// Resolves to true only when the reader chose [confirmLabel]; dismissing
/// the dialog any other way (cancel, back, tapping outside) is a no.
/// [routeName] names the route for the analytics funnel.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String routeName,
  String cancelLabel = 'cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    routeSettings: RouteSettings(name: routeName),
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      // Scrolls rather than overflowing at large text sizes.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: context.fonts.interface(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: context.fonts.body(
                fontSize: 14,
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SoftPillButton(
                    label: cancelLabel,
                    tint: colors.secondaryText,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SoftPillButton(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
