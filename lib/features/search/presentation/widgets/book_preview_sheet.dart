import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/collections.dart';
import '../../../library/domain/edition_filter.dart';
import '../../../library/domain/user_book.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/book_detail_page.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../../../library/presentation/widgets/shelf_selection_sheet.dart';
import 'book_rows.dart';

/// A Google Books volume the reader found but may not have: its cover,
/// title, author, year and pages, the blurb, and — the Goodreads "Want to
/// Read" pattern — one obvious button to add it to read, with reading,
/// finished and any other shelf beside it. A book already on the shelf
/// says where, and opens its book page instead.
///
/// Resolves to the add's result, or null when nothing was added.
Future<LibraryActionResult?> showBookPreviewSheet(
  BuildContext context,
  GoogleBook volume,
) {
  return showModalBottomSheet<LibraryActionResult>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'book_preview'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => BookPreviewSheet(volume: volume),
  );
}

class BookPreviewSheet extends StatefulWidget {
  const BookPreviewSheet({super.key, required this.volume});

  final GoogleBook volume;

  @override
  State<BookPreviewSheet> createState() => _BookPreviewSheetState();
}

class _BookPreviewSheetState extends State<BookPreviewSheet> {
  bool _adding = false;

  Future<void> _add(ShelfRef shelf) async {
    if (_adding) return;
    AppHaptics.selection();
    setState(() => _adding = true);
    final navigator = Navigator.of(context);
    LibraryActionResult result;
    try {
      result = await LibraryScope.read(context).addVolume(widget.volume, shelf);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookPreviewSheet',
        'Adding a book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure(
        "We couldn't add that book. Try again.",
      );
    }
    if (!mounted) return;
    setState(() => _adding = false);
    navigator.pop(result);
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
    final volume = widget.volume;
    final owned = library.findByGoogleBooksId(volume.id);
    final year = BookRow.publishedYear(volume.publishedDate);
    final facts = [
      ?year,
      if (volume.pageCount case final pages?) '$pages pages',
    ].join(' · ');
    final blurb = volume.description == null
        ? null
        : plainTextFromHtml(volume.description!);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: BookCover(
                    title: volume.title,
                    author: volume.authorLine,
                    coverUrl: volume.thumbnailUrl,
                    isbn: volume.isbn13 ?? volume.isbn10,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          volume.title,
                          style: context.fonts.bookTitle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        volume.authorLine,
                        style: context.fonts.body(
                          fontSize: 14,
                          color: colors.secondaryText,
                        ),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          facts,
                          style: context.fonts.interface(
                            fontSize: 12,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (blurb != null && blurb.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                blurb,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: context.fonts.body(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.primaryText,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (owned != null) ...[
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
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  openBookDetail(navigator.context, owned);
                },
                child: Text(
                  'open book',
                  style: context.fonts.interface(fontSize: 15),
                ),
              ),
            ] else ...[
              FilledButton(
                key: const ValueKey('preview-want-to-read'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                  minimumSize: const Size.fromHeight(48),
                ),
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
                          : () => _add(
                              const StatusShelfRef(ReadingStatus.reading),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _SecondaryButton(
                      key: const ValueKey('preview-finished'),
                      label: 'finished',
                      onPressed: _adding
                          ? null
                          : () => _add(
                              const StatusShelfRef(ReadingStatus.finished),
                            ),
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
          ],
        ),
      ),
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
