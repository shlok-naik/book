import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/domain/library_search.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/book_detail_page.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../../../shell/presentation/widgets/bottom_switcher.dart';
import '../../../shell/presentation/widgets/top_bar.dart';

/// The "search" tab — where the Memory tab used to be.
///
/// For now it searches the reader's own shelf (the same matching the
/// library page's search field uses) and opens a hit on its book page.
/// Google Books results and recommendations under the bar come next.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final query = _query.trim();
    final results = query.isEmpty
        ? const <LibraryBook>[]
        : [
            for (final entry in library.books)
              if (LibrarySearch.matches(
                entry,
                query,
                seriesName: library.seriesLabelFor(entry),
              ))
                entry,
          ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // Same insets as every other tab, so the gear doesn't move.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TopBar(title: 'search'),
              const SizedBox(height: AppSpacing.lg),
              _SearchField(
                controller: _controller,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: query.isNotEmpty && results.isEmpty
                    ? Text(
                        'no books on your shelf match "$query"',
                        style: context.fonts.interface(
                          fontSize: 14,
                          color: colors.secondaryText,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(
                          bottom: BottomSwitcher.pageFootprint,
                        ),
                        itemCount: results.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) =>
                            _ResultRow(entry: results[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.fonts.interface(
      fontSize: 15,
      color: colors.primaryText,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: colors.divider),
    );
    return TextField(
      key: const ValueKey('search-field'),
      controller: controller,
      onChanged: onChanged,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      style: style,
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: 'title or author',
        hintStyle: style.copyWith(color: colors.secondaryText),
        prefixIcon: Icon(Icons.search, size: 18, color: colors.secondaryText),
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

/// One book on the shelf: a small cover, the title and author. One
/// semantics node, a button that opens the book page.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.entry});

  final LibraryBook entry;

  static const _coverWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final book = entry.displayBook;
    return Semantics(
      button: true,
      label: '${book.title} by ${book.author}. On your shelf.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          AppHaptics.selection();
          openBookDetail(context, entry);
        },
        child: Row(
          children: [
            SizedBox(
              width: _coverWidth,
              child: BookCover(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                isbn: book.isbn13 ?? book.isbn10,
                rereadCount: entry.rereadCount,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.fonts.bookTitle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.fonts.body(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
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
