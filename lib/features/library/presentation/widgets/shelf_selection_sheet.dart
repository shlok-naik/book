import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/collections.dart';
import '../../domain/user_book.dart';
import '../library_scope.dart';

/// Every shelf a book can go on — the four built-in ones, then the
/// reader's own — with [current] ticked. Resolves to the one tapped, or
/// null when dismissed or when the current shelf is tapped again.
///
/// The button way to do what `move <book> <shelf>` and a drag on the
/// library page do; the caller moves the book through
/// `LibraryController.moveBook`, the same path both of those use.
Future<ShelfRef?> showShelfSelectionSheet(
  BuildContext context, {
  required ShelfRef current,
}) {
  return showModalBottomSheet<ShelfRef>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'select_shelf'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => ShelfSelectionSheet(current: current),
  );
}

class ShelfSelectionSheet extends StatelessWidget {
  const ShelfSelectionSheet({super.key, required this.current});

  final ShelfRef current;

  /// Built-in shelves in the order the library page shows them.
  static const builtIn = [
    StatusShelfRef(ReadingStatus.reading),
    StatusShelfRef(ReadingStatus.toBeRead),
    StatusShelfRef(ReadingStatus.finished),
    StatusShelfRef(ReadingStatus.dnf),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final shelves = <ShelfRef>[
      ...builtIn,
      for (final shelf in library.shelves) CustomShelfRef(shelf.id),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'move to shelf',
                style: context.fonts.interface(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final shelf in shelves)
                    _ShelfOption(
                      label: library.shelfName(shelf),
                      selected: shelf == current,
                      onTap: () {
                        if (shelf == current) {
                          Navigator.of(context).pop();
                          return;
                        }
                        AppHaptics.selection();
                        Navigator.of(context).pop(shelf);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfOption extends StatelessWidget {
  const _ShelfOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('shelf-option-$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.fonts.body(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? colors.accent : colors.primaryText,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 20, color: colors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
