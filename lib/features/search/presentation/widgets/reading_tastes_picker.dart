import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/reading_taste.dart';
import '../reading_tastes_controller.dart';

/// Every [ReadingTaste] as a tappable chip, the picked ones filled. Used by
/// onboarding and the settings sheet alike, so both look the same.
class ReadingTastesPicker extends StatelessWidget {
  const ReadingTastesPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<ReadingTaste> selected;
  final ValueChanged<Set<ReadingTaste>> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final taste in ReadingTaste.values)
          Semantics(
            button: true,
            selected: selected.contains(taste),
            label: taste.label,
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('taste-${taste.name}'),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () {
                AppHaptics.selection();
                final next = {...selected};
                if (!next.remove(taste)) next.add(taste);
                onChanged(next);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: selected.contains(taste)
                      ? colors.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: colors.accent),
                ),
                child: Text(
                  taste.label,
                  style: context.fonts.interface(
                    fontSize: 13,
                    color: selected.contains(taste)
                        ? colors.background
                        : colors.accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Settings' **profile → reading tastes** row: the picker in a sheet,
/// saving as the reader taps.
Future<void> showReadingTastesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'reading_tastes'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: ValueListenableBuilder<List<ReadingTaste>>(
          valueListenable: ReadingTastesController.tastes,
          builder: (context, tastes, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'what do you like to read?',
                  style: context.fonts.interface(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'shapes the recommendations on the search tab.',
                style: context.fonts.body(
                  fontSize: 13,
                  color: context.colors.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ReadingTastesPicker(
                selected: tastes.toSet(),
                onChanged: ReadingTastesController.select,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
