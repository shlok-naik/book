import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/edition_filter.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/book_detail_page.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../pages/volume_detail_page.dart';
import 'book_rows.dart';
import 'volume_shelf_actions.dart';

/// A Google Books volume the reader found but may not have: its cover,
/// title, author, year and pages, the blurb, [VolumeShelfActions] — and
/// **see all details**, which opens the full [VolumeDetailPage].
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

class BookPreviewSheet extends StatelessWidget {
  const BookPreviewSheet({super.key, required this.volume});

  final GoogleBook volume;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('preview-details'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.accent,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  unawaited(openVolumeDetails(navigator.context, volume));
                },
                icon: const Icon(Icons.info_outline, size: 18),
                label: Text(
                  'see all details',
                  style: context.fonts.interface(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            VolumeShelfActions(
              volume: volume,
              onResult: (result) => Navigator.of(context).pop(result),
              onOpenBook: () {
                final navigator = Navigator.of(context);
                final owned = LibraryScope.read(
                  context,
                ).findByGoogleBooksId(volume.id);
                navigator.pop();
                if (owned != null) {
                  unawaited(openBookDetail(navigator.context, owned));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
