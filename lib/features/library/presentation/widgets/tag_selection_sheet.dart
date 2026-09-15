import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/book_note.dart';
import '../../domain/collections.dart';
import '../controllers/book_detail_controller.dart';
import '../library_scope.dart';

/// A picker over every tag the reader has made ([LibraryController.tags]),
/// checked for the ones already on this book — tapping one applies or
/// removes it. Never makes a new tag itself: that's `make tag` or the
/// library's "+" panel, so a reader with none yet is pointed there instead
/// of typing one in here.
Future<void> showTagSelectionSheet(
  BuildContext context,
  BookDetailController detail,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    // Named so it shows up in the analytics funnel.
    routeSettings: const RouteSettings(name: 'select_tags'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => TagSelectionSheet(detail: detail),
  );
}

class TagSelectionSheet extends StatefulWidget {
  const TagSelectionSheet({super.key, required this.detail});

  final BookDetailController detail;

  @override
  State<TagSelectionSheet> createState() => _TagSelectionSheetState();
}

class _TagSelectionSheetState extends State<TagSelectionSheet> {
  /// Tag ids mid-toggle, so a second tap while one is still saving is
  /// ignored rather than sent twice.
  final _pending = <String>{};

  BookTag? _applied(ReaderTag tag, List<BookTag> current) {
    for (final t in current) {
      if (BookTag.normalize(t.tag) == BookTag.normalize(tag.name)) return t;
    }
    return null;
  }

  Future<void> _toggle(ReaderTag tag, BookTag? applied) async {
    if (_pending.contains(tag.id)) return;
    setState(() => _pending.add(tag.id));
    AppHaptics.selection();
    try {
      if (applied != null) {
        await widget.detail.removeTag(applied.id);
      } else {
        await widget.detail.addTag(tag.name);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'TagSelectionSheet',
        'Toggling a tag failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _pending.remove(tag.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final tags = LibraryScope.of(context).tags;

    return AnimatedBuilder(
      animation: widget.detail,
      builder: (context, _) {
        final current = widget.detail.tags.data ?? const <BookTag>[];
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
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
                      'select tags',
                      style: context.fonts.interface(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (tags.isEmpty)
                    Text(
                      "you haven't made any tags yet — make one from the "
                      "library's + panel.",
                      style: context.fonts.body(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final tag in tags)
                          _SelectableTagChip(
                            tag: tag,
                            selected: _applied(tag, current) != null,
                            busy: _pending.contains(tag.id),
                            onTap: () => _toggle(tag, _applied(tag, current)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SelectableTagChip extends StatelessWidget {
  const _SelectableTagChip({
    required this.tag,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final ReaderTag tag;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        label: selected ? 'Remove tag ${tag.name}' : 'Add tag ${tag.name}',
        excludeSemantics: true,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.accent.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 14, color: colors.accent),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  tag.name,
                  style: context.fonts.interface(
                    fontSize: 13,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
