import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/network/connectivity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/collections.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/domain/library_search.dart';
import '../../../library/domain/user_book.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/pages/book_detail_page.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../shell/presentation/widgets/bottom_switcher.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../controllers/book_search_controller.dart';
import '../reading_tastes_controller.dart';
import '../widgets/book_preview_sheet.dart';
import '../widgets/book_rows.dart';

/// The "search" tab — where the Memory tab used to be, modelled on
/// Goodreads' own search: one bar at the top ("title or author"), and
/// under it, before anything is typed, rows of recommended books to
/// scroll through sideways ([RecommendationSeeds] — free, built from the
/// reader's own shelf).
///
/// Once something is typed: the reader's own matching books first ("on
/// your shelf", opening their book page), then Google Books' results, each
/// with a "+" that adds it to read in one tap and opening
/// [showBookPreviewSheet] — the "want to read" button and the other
/// shelves — on a tap. Offline, only the shelf half answers.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _debounce = Duration(milliseconds: 400);
  static const _messageLifetime = Duration(seconds: 3);

  final _text = TextEditingController();
  BookSearchController? _search;
  Timer? _timer;

  String? _message;
  ConfirmationTone _tone = ConfirmationTone.neutral;
  Timer? _messageTimer;

  /// Volume ids mid-add, so a second tap on "+" isn't sent twice.
  final _adding = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) return;
    final library = LibraryScope.read(context);
    _search = BookSearchController(lookup: library.lookup);
    // After the first frame: the shelf may still be loading, and the
    // controller notifies synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRows());
    ReadingTastesController.tastes.addListener(_refreshRows);
  }

  void _refreshRows() {
    if (!mounted) return;
    final library = LibraryScope.read(context);
    if (!library.hasLoaded || ConnectivityController.isOffline.value) return;
    unawaited(
      _search!.loadRecommendations(
        library.books,
        tastes: ReadingTastesController.tastes.value,
      ),
    );
  }

  @override
  void dispose() {
    ReadingTastesController.tastes.removeListener(_refreshRows);
    _timer?.cancel();
    _messageTimer?.cancel();
    _search?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted && !ConnectivityController.isOffline.value) {
        unawaited(_search!.search(value));
      }
    });
  }

  void _showResult(LibraryActionResult? result) {
    if (result == null || !mounted) return;
    if (result.success) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
    final message = result.message;
    if (message == null) return;
    setState(() {
      _message = message;
      _tone = result.success
          ? ConfirmationTone.success
          : ConfirmationTone.failure;
    });
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _preview(GoogleBook volume) async {
    AppHaptics.selection();
    try {
      _showResult(await showBookPreviewSheet(context, volume));
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SearchPage',
        'Opening a book preview failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _quickAdd(GoogleBook volume) async {
    if (!_adding.add(volume.id)) return;
    setState(() {});
    AppHaptics.selection();
    LibraryActionResult result;
    try {
      result = await LibraryScope.read(
        context,
      ).addVolume(volume, const StatusShelfRef(ReadingStatus.toBeRead));
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SearchPage',
        'Adding a book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure(
        "We couldn't add that book. Try again.",
      );
    }
    if (!mounted) return;
    setState(() => _adding.remove(volume.id));
    _showResult(result);
  }

  void _openShelfBook(LibraryBook entry) {
    AppHaptics.selection();
    unawaited(openBookDetail(context, entry));
  }

  @override
  Widget build(BuildContext context) {
    final library = LibraryScope.of(context);
    final query = _text.text.trim();
    if (library.hasLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRows());
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
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
                  _SearchField(controller: _text, onChanged: _onChanged),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: ConnectivityController.isOffline,
                      builder: (context, offline, _) => ListenableBuilder(
                        listenable: _search!,
                        builder: (context, _) => query.isEmpty
                            ? _recommendations(offline)
                            : _results(library, query, offline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_message case final message?)
              Positioned(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: BottomSwitcher.pageFootprint + AppSpacing.sm,
                child: Semantics(
                  liveRegion: true,
                  child: ConfirmationPill(
                    message: message,
                    tone: _tone,
                    floating: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(LibraryController library, String query, bool offline) {
    final colors = context.colors;
    final search = _search!;
    final shelf = [
      for (final entry in library.books)
        if (LibrarySearch.matches(
          entry,
          query,
          seriesName: library.seriesLabelFor(entry),
        ))
          entry,
    ];
    final onShelfIds = {
      for (final entry in library.books) entry.book.googleBooksId,
    };
    final volumes = [
      for (final volume in search.results)
        if (!onShelfIds.contains(volume.id)) volume,
    ];

    Widget note(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      ),
    );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: BottomSwitcher.pageFootprint),
      children: [
        if (shelf.isNotEmpty) ...[
          const ListHeading('on your shelf'),
          for (final entry in shelf)
            BookRow.shelf(
              key: ValueKey('search-shelf-${entry.id}'),
              entry: entry,
              shelfName: library.shelfName(library.placementOf(entry)),
              onTap: () => _openShelfBook(entry),
            ),
        ],
        const ListHeading('google books'),
        if (offline)
          note('searching google books needs a connection.')
        else if (search.isSearching && volumes.isEmpty)
          note('searching…')
        else if (search.errorMessage case final error?)
          note(error)
        else if (search.query == query && volumes.isEmpty)
          note(
            shelf.isEmpty
                ? 'no books match "$query".'
                : 'nothing more on google books for "$query".',
          )
        else
          for (final volume in volumes)
            BookRow.volume(
              key: ValueKey('search-volume-${volume.id}'),
              volume: volume,
              onTap: () => _preview(volume),
              trailing: _AddButton(
                key: ValueKey('search-add-${volume.id}'),
                title: volume.title,
                busy: _adding.contains(volume.id),
                onTap: () => _quickAdd(volume),
              ),
            ),
      ],
    );
  }

  Widget _recommendations(bool offline) {
    final colors = context.colors;
    final rows = _search!.recommendations;
    if (offline) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Text(
          'recommendations need a connection — your own books can still be '
          'searched.',
          style: context.fonts.interface(
            fontSize: 13,
            height: 1.5,
            color: colors.secondaryText,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: BottomSwitcher.pageFootprint),
      children: [
        for (final row in rows) ...[
          ListHeading(row.seed.label),
          if (row.loading)
            const SizedBox(height: _RecommendationStrip.height)
          else if (row.error case final error?)
            Text(
              error,
              style: context.fonts.interface(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            )
          else
            _RecommendationStrip(books: row.books, onTap: _preview),
        ],
      ],
    );
  }
}

/// A sideways-scrolling row of recommended covers, each with its title —
/// Goodreads' discover rows.
class _RecommendationStrip extends StatelessWidget {
  const _RecommendationStrip({required this.books, required this.onTap});

  final List<GoogleBook> books;
  final ValueChanged<GoogleBook> onTap;

  static const _coverWidth = 92.0;
  static const height = _coverWidth / BookCover.aspectRatio + 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final volume = books[index];
          return Semantics(
            button: true,
            label: '${volume.title} by ${volume.authorLine}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('recommended-${volume.id}'),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => onTap(volume),
              child: SizedBox(
                width: _coverWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCover(
                      title: volume.title,
                      author: volume.authorLine,
                      coverUrl: volume.thumbnailUrl,
                      isbn: volume.isbn13 ?? volume.isbn10,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      volume.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.fonts.bookTitle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The "+" beside a Google Books result: adds it to read in one tap.
class _AddButton extends StatelessWidget {
  const _AddButton({
    super.key,
    required this.title,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Add $title to read',
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: busy
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              )
            : InkResponse(
                onTap: onTap,
                radius: 22,
                child: Icon(
                  Icons.add_circle_outline,
                  size: 22,
                  color: colors.accent,
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
      // Enter submits without closing the keyboard (a TextField's default
      // is to unfocus on the action button).
      onEditingComplete: () {},
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
