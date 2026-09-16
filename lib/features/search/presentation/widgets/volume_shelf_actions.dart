import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/collections.dart';
import '../../../library/domain/user_book.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/book_detail_page.dart';
import '../../../library/presentation/widgets/shelf_selection_sheet.dart';

/// What a Google Books volume offers the reader, Goodreads-style: one
/// obvious **want to read** button with reading / finished / other… beside
/// it — or, once it's on the shelf, where it is and **open book**.
///
/// Shared by the preview sheet and the book details page. Every add goes
/// through `LibraryController.addVolume`; [onResult] hears how it went.
class VolumeShelfActions extends StatefulWidget {
  const VolumeShelfActions({
    super.key,
    required this.volume,
    required this.onResult,
    this.onOpenBook,
  });

  final GoogleBook volume;
  final ValueChanged<LibraryActionResult> onResult;

  /// Replaces the default push of the book page — the preview sheet closes
  /// itself first.
  final VoidCallback? onOpenBook;

  @override
  State<VolumeShelfActions> createState() => _VolumeShelfActionsState();
}

class _VolumeShelfActionsState extends State<VolumeShelfActions> {
  bool _adding = false;

  Future<void> _add(ShelfRef shelf) async {
    if (_adding) return;
    AppHaptics.selection();
    setState(() => _adding = true);
    LibraryActionResult result;
    try {
      result = await LibraryScope.read(context).addVolume(widget.volume, shelf);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'VolumeShelfActions',
        'Adding a book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure("Couldn't add book.");
    }
    if (!mounted) return;
    setState(() => _adding = false);
    widget.onResult(result);
  }

  Future<void> _pickOtherShelf() async {
    final picked = await showShelfSelectionSheet(
      context,
      current: const StatusShelfRef(ReadingStatus.toBeRead),
    );
    if (picked != null && mounted) await _add(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final owned = library.findByGoogleBooksId(widget.volume.id);
    final primary = FilledButton.styleFrom(
      backgroundColor: colors.accent,
      foregroundColor: colors.background,
      minimumSize: const Size.fromHeight(48),
    );

    if (owned != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'on your shelf · ${library.shelfName(library.placementOf(owned))}',
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            key: const ValueKey('preview-open-book'),
            style: primary,
            onPressed:
                widget.onOpenBook ?? () => openBookDetail(context, owned),
            child: Text(
              'open book',
              style: context.fonts.interface(fontSize: 15),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const ValueKey('preview-want-to-read'),
          style: primary,
          onPressed: _adding
              ? null
              : () => _add(const StatusShelfRef(ReadingStatus.toBeRead)),
          child: Text(
            'want to read',
            style: context.fonts.interface(fontSize: 15),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                key: const ValueKey('preview-reading'),
                label: 'reading',
                onPressed: _adding
                    ? null
                    : () => _add(const StatusShelfRef(ReadingStatus.reading)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SecondaryButton(
                key: const ValueKey('preview-finished'),
                label: 'finished',
                onPressed: _adding
                    ? null
                    : () => _add(const StatusShelfRef(ReadingStatus.finished)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _SecondaryButton(
                key: const ValueKey('preview-other-shelf'),
                label: 'other…',
                onPressed: _adding ? null : _pickOtherShelf,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.accent),
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.fonts.interface(fontSize: 13),
      ),
    );
  }
}
