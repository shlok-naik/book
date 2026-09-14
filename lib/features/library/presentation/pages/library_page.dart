import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/book_series.dart';
import '../../domain/collections.dart';
import '../../domain/library_book.dart';
import '../../domain/library_search.dart';
import '../../domain/user_book.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import '../series_tile_style_controller.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_tile.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/series_cover.dart';
import 'book_detail_page.dart';
import 'series_page.dart';

/// One shelf section on the page: which shelf it holds and what it's
/// called — on screen (lowercase, like every heading in the app) and to a
/// screen reader.
typedef _Shelf = ({ShelfRef ref, String label, String spoken});

/// The built-in sections a reader is actively working through, first.
const List<_Shelf> _activeShelves = [
  (
    ref: StatusShelfRef(ReadingStatus.reading),
    label: 'reading',
    spoken: 'Reading',
  ),
  (
    ref: StatusShelfRef(ReadingStatus.toBeRead),
    label: 'to read',
    spoken: 'To read',
  ),
];

/// The built-in sections a reader is done with, last.
const List<_Shelf> _closedShelves = [
  (
    ref: StatusShelfRef(ReadingStatus.finished),
    label: 'finished',
    spoken: 'Finished',
  ),
  (
    ref: StatusShelfRef(ReadingStatus.dnf),
    label: 'did not finish',
    spoken: 'Did not finish',
  ),
];

/// Every section on the page, in page order: reading, to read, then the
/// reader's own shelves oldest first, then finished and did not finish —
/// a new custom shelf lands above finished rather than at the very bottom.
List<_Shelf> _shelvesOf(LibraryController controller) => [
  ..._activeShelves,
  for (final shelf in controller.shelves)
    (ref: CustomShelfRef(shelf.id), label: shelf.name, spoken: shelf.name),
  ..._closedShelves,
];

/// A stable key fragment for a section — `reading`, `custom-<id>`.
String _shelfKey(ShelfRef ref) => switch (ref) {
  StatusShelfRef(:final status) => status.name,
  CustomShelfRef(:final shelfId) => 'custom-$shelfId',
};

/// The reader's shelf: the four built-in sections — reading, to read,
/// finished, did not finish — then one per shelf the reader made, each a
/// cover grid, always all of them, whether or not a section has anything in
/// it yet. An empty section is its heading over a quiet empty area, not copy
/// telling the reader it's empty.
///
/// Purely a view — it reads [LibraryController] out of [LibraryScope]
/// and rebuilds when it notifies, so a progress update from the log page
/// shows up here with no refresh of any kind.
///
/// ## Moving books
///
/// Tapping a book (or Enter/Space on a focused one) opens its
/// [BookDetailPage]. Pressing and holding picks it up. Where it can land is
/// shown only through hover/active states — no "drop here" prompts:
///
/// * another tile — an accent insertion bar on the side it will land
///   (left half = before, right half = after);
/// * a section's heading — the heading takes the accent, and the book lands
///   first in that section, so a long section doesn't need scrolling to
///   its end;
/// * an empty section's area — outlined and tinted while hovered.
///
/// The drop is [LibraryController.moveBook], which applies the same
/// shelf-change side effects as a typed `move` command and rolls the
/// whole shelf back if it can't be saved. While one move is being saved,
/// no book can be picked up and keyboard moves are ignored, so two moves
/// never race each other's rollback.
///
/// The same moves exist without a pointer: screen-reader custom actions
/// on every tile, and keyboard shortcuts on a focused one (Alt+↑/↓ to the
/// previous/next shelf, Alt+←/→ earlier/later within its shelf).
///
/// ## Making shelves, tags and series
///
/// The "+" beside the search icon opens [showCollectionsSheet]: a panel with
/// shelves, tags and series tabs, each making one through the same
/// `LibraryController` function its `make` command uses. A shelf made there
/// appears here as a new empty section straight away.
///
/// ## Series and search
///
/// Books filed under a series also appear, grouped, in a "series" row above
/// the shelves; a group opens [SeriesPage]. The search icon beside the gear
/// filters everything to books whose title, author, series or tags contain
/// every word typed (see [LibrarySearch]). While searching, empty shelves
/// are hidden, nothing can be dragged (a drop position in a filtered list
/// doesn't map to a real shelf order), and a search with no matches says so
/// — the one piece of copy on this page, since an empty screen would read as
/// a broken library.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  /// The floating bottom bar's footprint, so the last row of covers
  /// isn't hidden behind it — same constant the streaks page uses.
  static const _barFootprint = 108.0;

  static const _messageLifetime = Duration(seconds: 3);

  final _scroll = ScrollController();

  /// The `user_books` id of the book currently held, or null.
  String? _draggingId;

  /// True while a move is being saved — see the class doc comment.
  bool _moving = false;

  /// Scrolls the page while a held book hovers near the top or bottom
  /// edge — a drag can't reach a section that's off screen otherwise.
  Timer? _autoScroll;
  double _autoScrollVelocity = 0;

  String? _message;
  Timer? _messageTimer;

  bool _searching = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();

  /// Shelves collapsed to just their heading — in-memory only, so a fresh
  /// visit to the library always starts from this same default rather than
  /// remembering a prior toggle. Finished and did not finish start closed —
  /// a reader opens the library to see what to read next, not what's
  /// behind them. Ignored while searching: collapsing a shelf and then
  /// finding a match in it should still show that match rather than hide
  /// it.
  final _collapsed = <ShelfRef>{
    const StatusShelfRef(ReadingStatus.finished),
    const StatusShelfRef(ReadingStatus.dnf),
  };

  void _toggleCollapsed(ShelfRef shelf) {
    AppHaptics.selection();
    setState(() {
      if (!_collapsed.add(shelf)) _collapsed.remove(shelf);
    });
  }

  Future<void> _openCollections() async {
    AppHaptics.selection();
    try {
      await showCollectionsSheet(context);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'LibraryPage',
        'Opening the collections panel failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage("We couldn't open that. Try again.");
    }
  }

  /// Every tag on the shelf by `user_books` id, fetched when search opens
  /// so a tag can be searched for. Empty if that fetch fails — search then
  /// just doesn't match tags.
  Map<String, List<String>> _tagsByBook = const {};

  String get _query => _searchText.text.trim();

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: load() notifies synchronously
    // to raise its loading flag, and notifying mid-build is illegal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LibraryScope.read(context).load();
    });
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _messageTimer?.cancel();
    _searchText.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- search

  void _toggleSearch() {
    AppHaptics.selection();
    if (_searching) {
      _searchText.clear();
      _searchFocus.unfocus();
      setState(() => _searching = false);
      return;
    }
    setState(() => _searching = true);
    _searchFocus.requestFocus();
    unawaited(_loadTags());
  }

  Future<void> _loadTags() async {
    try {
      final tags = await LibraryScope.read(context).notes.fetchAllTags();
      if (!mounted) return;
      final byBook = <String, List<String>>{};
      for (final tag in tags) {
        (byBook[tag.userBookId] ??= []).add(tag.tag);
      }
      setState(() => _tagsByBook = byBook);
    } on Object catch (error) {
      AppLogger.info('LibraryPage', 'Tags unavailable for search: $error');
    }
  }

  bool _visible(LibraryBook entry) {
    if (!_searching) return true;
    final seriesId = entry.seriesId;
    return LibrarySearch.matches(
      entry,
      _query,
      tags: _tagsByBook[entry.id] ?? [],
      seriesName: seriesId == null
          ? null
          : LibraryScope.read(context).seriesById(seriesId)?.name,
    );
  }

  // --------------------------------------------------------------- dragging

  void _onDragStarted(String id) {
    AppHaptics.selection();
    setState(() => _draggingId = id);
  }

  /// Called for every way a drag can end — dropped, dropped nowhere,
  /// cancelled by the system — so the page never stays in its "holding a
  /// book" state or keeps auto-scrolling after the finger lifts.
  void _onDragEnded() {
    _stopAutoScroll();
    if (mounted && _draggingId != null) setState(() => _draggingId = null);
  }

  /// Starts, adjusts or stops edge auto-scroll from the held book's
  /// pointer position. Speed ramps up the deeper into the edge band.
  void _onDragUpdate(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !_scroll.hasClients) return;
    final local = box.globalToLocal(globalPosition);
    const band = 96.0;
    const maxSpeed = 18.0;
    final bottomEdge = box.size.height - _barFootprint;

    double velocity = 0;
    if (local.dy < band) {
      velocity = -maxSpeed * (1 - (local.dy / band).clamp(0.0, 1.0));
    } else if (local.dy > bottomEdge - band) {
      velocity =
          maxSpeed * ((local.dy - (bottomEdge - band)) / band).clamp(0.0, 1.0);
    }

    _autoScrollVelocity = velocity;
    if (velocity == 0) {
      _stopAutoScroll();
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!mounted || !_scroll.hasClients) return _stopAutoScroll();
        final position = _scroll.position;
        final next = (position.pixels + _autoScrollVelocity).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (next != position.pixels) _scroll.jumpTo(next);
      });
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _autoScrollVelocity = 0;
  }

  /// Every move — drag, keyboard shortcut, screen-reader action — ends
  /// here. Reports the outcome as a haptic and the confirmation pill.
  ///
  /// [LibraryController.moveBook] reports failures as results rather than
  /// throwing; the catch below is for anything it didn't anticipate, so an
  /// unexpected error still reads as a failed move rather than an unhandled
  /// exception with the pill never appearing.
  Future<void> _move(String id, ShelfRef shelf, int index) async {
    _onDragEnded();
    if (_moving) return;
    setState(() => _moving = true);

    LibraryActionResult result;
    try {
      result = await LibraryScope.read(context).moveBook(id, shelf, index);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'LibraryPage',
        'Moving a book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure(
        "We couldn't move that book. Try again.",
      );
    }
    if (!mounted) return;
    setState(() => _moving = false);

    // A drop back where it started returns failure with no message:
    // nothing happened, so there is nothing to feel or read.
    final message = result.message;
    if (result.success) {
      AppHaptics.accepted();
    } else if (message != null) {
      AppHaptics.rejected();
    }
    if (message != null) _showMessage(message);
  }

  Future<void> _open(LibraryBook entry) async {
    try {
      await openBookDetail(context, entry);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'LibraryPage',
        'Opening a book failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showMessage("We couldn't open that book. Try again.");
    }
  }

  void _showMessage(String message) {
    setState(() => _message = message);
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () {
      if (mounted) setState(() => _message = null);
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final controller = LibraryScope.of(context);
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              color: colors.accent,
              backgroundColor: colors.surface,
              onRefresh: controller.load,
              child: CustomScrollView(
                controller: _scroll,
                // Always scrollable so pull-to-refresh works even when the
                // shelf is short or errored.
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      searching: _searching,
                      onToggleSearch: _toggleSearch,
                      onOpenCollections: _openCollections,
                      searchField: _SearchField(
                        controller: _searchText,
                        focusNode: _searchFocus,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  ..._body(controller),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: _barFootprint + AppSpacing.md),
                  ),
                ],
              ),
            ),
            if (_message case final message?)
              Positioned(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                bottom: _barFootprint + AppSpacing.sm,
                // A live region, so the outcome of a move is read out
                // without the reader having to go looking for it.
                child: Semantics(
                  liveRegion: true,
                  child: ConfirmationPill(message: message),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(LibraryController controller) {
    // Errors and the first-load message replace the shelf; once books are
    // on screen a failed refresh leaves them there rather than blanking a
    // working page.
    if (controller.errorMessage != null && controller.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Message(
            text: controller.errorMessage!,
            actionLabel: 'Try again',
            onAction: controller.load,
          ),
        ),
      ];
    }
    if (controller.isLoading && controller.isEmpty) {
      return const [
        SliverToBoxAdapter(child: _Message(text: 'Loading your library…')),
      ];
    }

    final dragging = _draggingId != null;
    final filtering = _searching && _query.isNotEmpty;
    final groups = [
      for (final group in controller.seriesGroups)
        if (!filtering ||
            group.entries.any(_visible) ||
            LibrarySearch.normalize(
              group.name,
            ).contains(LibrarySearch.normalize(_query)))
          group,
    ];
    final shelves = _shelvesOf(controller);
    final sections = {
      for (final shelf in shelves)
        shelf.ref: [
          for (final entry in controller.shelfSection(shelf.ref))
            if (!filtering || _visible(entry)) entry,
        ],
    };
    // A series with more than one book, all shelved in the same place, is
    // shown there as one grouped tile rather than a tile per book — never
    // while searching, since a search result is one specific book, not the
    // whole series it belongs to.
    final collapsedByShelf = <ShelfRef, List<SeriesGroup>>{};
    if (!filtering) {
      for (final group in controller.seriesGroups) {
        if (group.entries.length < 2) continue;
        final refs = {
          for (final entry in group.entries) ShelfRef.of(entry.progress),
        };
        if (refs.length != 1) continue;
        (collapsedByShelf[refs.single] ??= []).add(group);
      }
    }

    if (filtering &&
        groups.isEmpty &&
        sections.values.every((entries) => entries.isEmpty)) {
      return [
        SliverToBoxAdapter(child: _Message(text: 'no books match "$_query".')),
      ];
    }

    return [
      for (final shelf in shelves) ...[
        // Under the reader's own shelves, above finished/did not finish —
        // series belong with what's still in play, not above everything.
        if (shelf.ref == _closedShelves.first.ref && groups.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SeriesHeading()),
          SliverToBoxAdapter(child: _SeriesRow(groups: groups)),
        ],
        if (!filtering || sections[shelf.ref]!.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeading(
              key: ValueKey('shelf-heading-${_shelfKey(shelf.ref)}'),
              shelf: shelf,
              count: sections[shelf.ref]!.length,
              dragging: dragging,
              collapsed: _collapsed.contains(shelf.ref) && !filtering,
              onToggleCollapse: () => _toggleCollapsed(shelf.ref),
              // Dropping on a heading puts the book first in that section.
              onAccept: (id) => _move(id, shelf.ref, 0),
            ),
          ),
          if (_collapsed.contains(shelf.ref) && !filtering)
            const SliverToBoxAdapter(child: SizedBox.shrink())
          else if (sections[shelf.ref]! case final entries when entries.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyShelf(
                key: ValueKey('empty-shelf-${_shelfKey(shelf.ref)}'),
                shelf: shelf,
                dragging: dragging,
                onAccept: (id) => _move(id, shelf.ref, 0),
              ),
            )
          else
            _BookGrid(
              entries: sections[shelf.ref]!,
              collapsedSeries: collapsedByShelf[shelf.ref] ?? const [],
              shelf: shelf.ref,
              shelves: shelves,
              // Finished and dropped books are shown faded, so the shelves
              // still in play stay the visually dominant ones. A custom
              // shelf holds books of any status, so it never is.
              dimmed:
                  shelf.ref == const StatusShelfRef(ReadingStatus.finished) ||
                  shelf.ref == const StatusShelfRef(ReadingStatus.dnf),
              draggingId: _draggingId,
              canDrag: !_moving && !_searching,
              onDragStarted: _onDragStarted,
              onDragUpdate: _onDragUpdate,
              onDragEnded: _onDragEnded,
              onMove: _move,
              onOpen: _open,
            ),
        ],
      ],
    ];
  }
}

/// A responsive cover grid — a fixed max tile width rather than a fixed
/// column count, so it holds up from a small phone to a tablet or a wide
/// browser window.
class _BookGrid extends StatelessWidget {
  const _BookGrid({
    required this.entries,
    required this.shelf,
    required this.shelves,
    required this.draggingId,
    required this.canDrag,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.onMove,
    required this.onOpen,
    this.collapsedSeries = const [],
    this.dimmed = false,
  });

  final List<LibraryBook> entries;

  /// Series entirely shelved here, more than one book each — shown as one
  /// grouped tile in place of their individual ones. See
  /// [_LibraryPageState._buildSlivers].
  final List<SeriesGroup> collapsedSeries;
  final ShelfRef shelf;

  /// Every section on the page, in page order — where keyboard and
  /// screen-reader moves can send a book.
  final List<_Shelf> shelves;
  final bool dimmed;
  final String? draggingId;
  final bool canDrag;
  final ValueChanged<String> onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;

  /// A book id moved to a section at an index within it.
  final void Function(String id, ShelfRef shelf, int index) onMove;
  final ValueChanged<LibraryBook> onOpen;

  static const _maxTileWidth = 150.0;

  /// Room under the cover for title, author, bar, and label. Fixed so
  /// tiles line up; the text inside ellipsizes to fit.
  static const textExtent = 86.0;

  @override
  Widget build(BuildContext context) {
    final groupedIds = {
      for (final group in collapsedSeries)
        for (final entry in group.entries) entry.id,
    };
    // Grouped books keep their real index into [entries] — the position
    // `onMove` and keyboard reordering act on — even though they're not
    // rendered as their own tile.
    final items = <Object>[
      ...collapsedSeries,
      for (var i = 0; i < entries.length; i++)
        if (!groupedIds.contains(entries[i].id)) (i, entries[i]),
    ];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent - AppSpacing.xl * 2;
          final columns = (width / _maxTileWidth).ceil().clamp(2, 5);
          final tileWidth = (width - AppSpacing.md * (columns - 1)) / columns;
          final tileHeight = tileWidth / BookCover.aspectRatio + textExtent;

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: tileWidth / tileHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = items[index];
              if (item is SeriesGroup) {
                return _SeriesGroupTile(
                  key: ValueKey('shelf-series-${item.id}'),
                  group: item,
                );
              }
              final (bookIndex, entry) = item as (int, LibraryBook);
              return _DraggableBookTile(
                // Keyed on the progress row so Flutter reuses the right
                // element when a book moves between sections.
                key: ValueKey(entry.id),
                entry: entry,
                index: bookIndex,
                isLast: bookIndex == entries.length - 1,
                shelf: shelf,
                shelves: shelves,
                size: Size(tileWidth, tileHeight),
                dimmed: dimmed,
                canDrag: canDrag,
                onDragStarted: onDragStarted,
                onDragUpdate: onDragUpdate,
                onDragEnded: onDragEnded,
                onMove: onMove,
                onOpen: onOpen,
              );
            }, childCount: items.length),
          );
        },
      ),
    );
  }
}

/// One shelf-grid tile standing in for every book of a series that's
/// entirely shelved together — laid out exactly like [BookTile] (same
/// cover footprint, same rows), so it reads as one more book on the
/// shelf rather than a different kind of thing: a [SeriesPatchworkCover]
/// where a cover goes, the series name where a title goes, "N books"
/// where the author goes, then the group's aggregate progress — how many
/// are finished, the rest's average completion, and (once any is rated)
/// their average rating. Never draggable: it represents more than one
/// shelf position at once, so there's no single place to drop it.
class _SeriesGroupTile extends StatelessWidget {
  const _SeriesGroupTile({super.key, required this.group});

  final SeriesGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entries = group.entries;

    final completions = [for (final entry in entries) ?entry.completion];
    final avgCompletion = completions.isEmpty
        ? null
        : completions.reduce((a, b) => a + b) / completions.length;

    final ratings = [
      for (final entry in entries)
        if (entry.isFinished && entry.rating != null) entry.rating!,
    ];
    final avgRating = ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;

    return Semantics(
      button: true,
      label: '${group.name} series, ${group.summary}.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          AppHaptics.selection();
          unawaited(openSeries(context, group));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeriesPatchworkCover(entries: entries),
            const SizedBox(height: AppSpacing.sm),
            Text(
              group.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fraunces(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${entries.length} books',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (avgCompletion != null) ...[
              _GroupProgressBar(
                value: avgCompletion,
                color: colors.accent,
                track: colors.divider,
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              _progressLabel(group, avgCompletion),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: group.finished == entries.length
                    ? colors.accent
                    : colors.secondaryText,
              ),
            ),
            if (avgRating != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 12, color: colors.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${_formatAverage(avgRating)} avg',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: colors.accent,
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

  static String _progressLabel(SeriesGroup group, double? avgCompletion) {
    final total = group.entries.length;
    if (group.finished == total) return 'all finished';
    final percent = avgCompletion == null
        ? null
        : (avgCompletion * 100).round();
    return percent == null
        ? '${group.finished}/$total finished'
        : '${group.finished}/$total finished · $percent% avg';
  }

  static String _formatAverage(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

/// [BookTile]'s own progress bar, kept as its own small copy the same way
/// `CurrentlyReadingCard`'s is — a hairline pair of containers rather
/// than a shared widget, so this file doesn't reach into book_tile.dart
/// for three lines of decoration.
class _GroupProgressBar extends StatelessWidget {
  const _GroupProgressBar({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  static const _height = 3.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * value.clamp(0.0, 1.0);
        return Stack(
          children: [
            Container(
              height: _height,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: _height,
              width: width,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MoveToShelfIntent extends Intent {
  const _MoveToShelfIntent(this.step);

  /// -1 for the previous shelf in page order, +1 for the next.
  final int step;
}

class _MoveWithinShelfIntent extends Intent {
  const _MoveWithinShelfIntent(this.step);

  /// -1 for one place earlier, +1 for one place later.
  final int step;
}

/// One tile that can be tapped or activated from the keyboard (open the
/// detail page), held and dragged (pick it up), and dropped onto (insert
/// the held book before or after it, depending on which half it's
/// released over).
class _DraggableBookTile extends StatefulWidget {
  const _DraggableBookTile({
    super.key,
    required this.entry,
    required this.index,
    required this.isLast,
    required this.shelf,
    required this.shelves,
    required this.size,
    required this.dimmed,
    required this.canDrag,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.onMove,
    required this.onOpen,
  });

  final LibraryBook entry;
  final int index;
  final bool isLast;
  final ShelfRef shelf;
  final List<_Shelf> shelves;
  final Size size;
  final bool dimmed;
  final bool canDrag;
  final ValueChanged<String> onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnded;
  final void Function(String id, ShelfRef shelf, int index) onMove;
  final ValueChanged<LibraryBook> onOpen;

  @override
  State<_DraggableBookTile> createState() => _DraggableBookTileState();
}

class _DraggableBookTileState extends State<_DraggableBookTile> {
  /// Which side of this tile a held book is hovering on, or null when
  /// none is — drives the insertion bar.
  bool? _hoverAfter;

  bool _focused = false;

  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
        const _MoveToShelfIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
        const _MoveToShelfIntent(1),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
        const _MoveWithinShelfIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
        const _MoveWithinShelfIntent(1),
  };

  /// Whether a feedback whose top-left is at [globalTopLeft] is centred
  /// over this tile's right half.
  bool _isAfter(Offset globalTopLeft) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final center = globalTopLeft + widget.size.center(Offset.zero);
    return box.globalToLocal(center).dx > box.size.width / 2;
  }

  BookTile _tile() => BookTile(
    entry: widget.entry,
    cover: BookCover(
      title: widget.entry.book.title,
      author: widget.entry.book.author,
      // The owned edition's cover when the reader picked one.
      coverUrl: widget.entry.displayBook.coverUrl,
      dimmed: widget.dimmed,
    ),
  );

  void _moveToShelf(int step) {
    final shelves = widget.shelves;
    final current = shelves.indexWhere((s) => s.ref == widget.shelf);
    final target = current + step;
    if (target < 0 || target >= shelves.length) return;
    widget.onMove(widget.entry.id, shelves[target].ref, 0);
  }

  void _moveWithinShelf(int step) {
    if (step < 0 && widget.index == 0) return;
    if (step > 0 && widget.isLast) return;
    // +2 to move later, not +1: the drop index counts the book itself,
    // which is removed before inserting (see ShelfRules.orderAfterDrop).
    widget.onMove(
      widget.entry.id,
      widget.shelf,
      step < 0 ? widget.index - 1 : widget.index + 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;

    final interactive = FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      shortcuts: _shortcuts,
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onOpen(entry),
        ),
        _MoveToShelfIntent: CallbackAction<_MoveToShelfIntent>(
          onInvoke: (intent) => _moveToShelf(intent.step),
        ),
        _MoveWithinShelfIntent: CallbackAction<_MoveWithinShelfIntent>(
          onInvoke: (intent) => _moveWithinShelf(intent.step),
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(entry),
        child: _tile(),
      ),
    );

    final draggable = LongPressDraggable<String>(
      data: entry.id,
      // Zero while another move is still being saved.
      maxSimultaneousDrags: widget.canDrag ? 1 : 0,
      hapticFeedbackOnStart: false, // AppHaptics owns what a buzz means.
      onDragStarted: () => widget.onDragStarted(entry.id),
      onDragUpdate: (details) => widget.onDragUpdate(details.globalPosition),
      onDragEnd: (_) => widget.onDragEnded(),
      onDraggableCanceled: (_, _) => widget.onDragEnded(),
      onDragCompleted: widget.onDragEnded,
      // Width only: the tile's own column decides its height, since the
      // overlay it's drawn in has slightly different text metrics from the
      // grid cell and a fixed height clips by a few pixels.
      feedback: SizedBox(
        width: widget.size.width,
        child: Material(
          type: MaterialType.transparency,
          child: Transform.scale(
            scale: 1.05,
            child: Opacity(opacity: 0.9, child: _tile()),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: _tile()),
      // Merged, so the tile's one-sentence label and these actions are a
      // single node to a screen reader rather than a label with nothing to
      // do and an unlabelled node full of actions.
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint:
              'Double tap to open. Use actions to move it, or press and '
              'hold to drag.',
          customSemanticsActions: _moveActions(),
          child: interactive,
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != entry.id,
      onMove: (details) {
        final after = _isAfter(details.offset);
        if (after != _hoverAfter) setState(() => _hoverAfter = after);
      },
      onLeave: (_) {
        if (_hoverAfter != null) setState(() => _hoverAfter = null);
      },
      onAcceptWithDetails: (details) {
        final after = _isAfter(details.offset);
        setState(() => _hoverAfter = null);
        widget.onMove(
          details.data,
          widget.shelf,
          widget.index + (after ? 1 : 0),
        );
      },
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty ? _hoverAfter : null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            draggable,
            // Keyboard focus ring around the cover.
            if (_focused)
              Positioned(
                left: -3,
                top: -3,
                right: -3,
                bottom: _BookGrid.textExtent - 3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm + 3),
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                  ),
                ),
              ),
            if (hover != null)
              Positioned(
                top: 0,
                bottom: _BookGrid.textExtent,
                left: hover ? null : -AppSpacing.sm - 1.5,
                right: hover ? -AppSpacing.sm - 1.5 : null,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Screen-reader equivalents of dragging: move to each other shelf, and
  /// nudge earlier/later within this one. A drag is unusable without
  /// sight; these are the same moves by another route.
  Map<CustomSemanticsAction, VoidCallback> _moveActions() {
    final id = widget.entry.id;
    return {
      for (final shelf in widget.shelves)
        if (shelf.ref != widget.shelf)
          CustomSemanticsAction(label: 'Move to ${shelf.label}'): () =>
              widget.onMove(id, shelf.ref, 0),
      if (widget.index > 0)
        const CustomSemanticsAction(label: 'Move earlier'): () =>
            _moveWithinShelf(-1),
      if (!widget.isLast)
        const CustomSemanticsAction(label: 'Move later'): () =>
            _moveWithinShelf(1),
    };
  }
}

/// A section's heading. Also a drop target: releasing a held book on it
/// puts the book first in that section. While a book is held, hovering
/// the heading turns it and a short underline accent — the only signal,
/// no instructional text.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    super.key,
    required this.shelf,
    required this.count,
    required this.dragging,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onAccept,
  });

  final _Shelf shelf;
  final int count;
  final bool dragging;

  /// Whether this shelf is showing just its heading right now.
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xs,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  label:
                      '${shelf.spoken}, $count ${count == 1 ? 'book' : 'books'}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 150),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: active ? colors.accent : colors.secondaryText,
                        ),
                        child: Text(
                          shelf.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 2,
                        width: active ? 32 : 0,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Collapses the shelf to just this heading — the covers below
              // are what take up room on a long shelf, not the heading, so
              // this is what a reader taps to get a whole shelf out of the
              // way without leaving the page.
              Semantics(
                button: true,
                label: collapsed
                    ? 'Show ${shelf.spoken.toLowerCase()} books'
                    : 'Hide ${shelf.spoken.toLowerCase()} books',
                excludeSemantics: true,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: InkResponse(
                    onTap: onToggleCollapse,
                    radius: 16,
                    child: AnimatedRotation(
                      duration: const Duration(milliseconds: 150),
                      turns: collapsed ? -0.25 : 0,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// An empty section's area: a quiet outlined space the height of a short
/// row, so an empty shelf still reads as a shelf and still has somewhere
/// to drop a book. Deliberately wordless. Its state is shown by outline
/// alone: a hairline normally, the accent at rest while any book is held
/// (it's a valid target), and a thicker accent with a tint while hovered.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({
    super.key,
    required this.shelf,
    required this.dragging,
    required this.onAccept,
  });

  final _Shelf shelf;
  final bool dragging;
  final ValueChanged<String> onAccept;

  static const height = 96.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: DragTarget<String>(
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidates, _) {
          final hovered = candidates.isNotEmpty;
          final border = hovered
              ? colors.accent
              : dragging
              ? colors.accent.withValues(alpha: 0.45)
              : colors.divider;
          return Semantics(
            // Heard, not seen: the heading above already names the shelf
            // and its count, so this only says what a sighted reader can
            // see at a glance.
            label: '${shelf.spoken} shelf is empty',
            container: true,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: height,
              decoration: BoxDecoration(
                color: hovered
                    ? colors.accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: border, width: hovered ? 2 : 1),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.searching,
    required this.onToggleSearch,
    required this.onOpenCollections,
    required this.searchField,
  });

  final bool searching;
  final VoidCallback onToggleSearch;

  /// The "+" — opens the shelves/tags/series panel.
  final VoidCallback onOpenCollections;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TopBar(
            title: 'library',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderIcon(
                  key: const ValueKey('library-make-collections'),
                  icon: Icons.add,
                  label: 'Make a shelf, tag or series',
                  color: colors.secondaryText,
                  onTap: onOpenCollections,
                ),
                _HeaderIcon(
                  icon: searching ? Icons.close : Icons.search,
                  label: searching ? 'Close search' : 'Search library',
                  color: colors.secondaryText,
                  onTap: onToggleSearch,
                ),
              ],
            ),
          ),
          if (searching) ...[
            const SizedBox(height: AppSpacing.sm),
            searchField,
          ],
        ],
      ),
    );
  }
}

/// One 44×44 icon button in the library header — the "+" and search share
/// it so they line up exactly.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = GoogleFonts.jetBrainsMono(
      fontSize: 15,
      color: colors.primaryText,
    );
    return TextField(
      key: const ValueKey('library-search'),
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      style: style,
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: 'title, author, series or tag',
        hintStyle: style.copyWith(color: colors.secondaryText),
        prefixIcon: Icon(Icons.search, size: 18, color: colors.secondaryText),
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

class _SeriesHeading extends StatelessWidget {
  const _SeriesHeading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xs,
          AppSpacing.xl,
          AppSpacing.sm,
        ),
        child: Text(
          'series',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.colors.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// One horizontally scrolling row of series groups — a fan of up to three
/// covers, the series name and "3 books · 1 finished". Tapping opens
/// [SeriesPage].
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.groups});

  final List<SeriesGroup> groups;

  static const _tileWidth = 132.0;
  static const _coverWidth = 72.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: _coverWidth / BookCover.aspectRatio + 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Semantics(
            button: true,
            label: '${group.name} series, ${group.summary}.',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('series-${group.id}'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                AppHaptics.selection();
                unawaited(openSeries(context, group));
              },
              child: SizedBox(
                width: _tileWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: SeriesTileStyleController.patchwork,
                      builder: (context, patchwork, _) => patchwork
                          ? SizedBox(
                              width: _coverWidth,
                              child: SeriesPatchworkCover(
                                entries: group.entries,
                              ),
                            )
                          // Self-sizing, and wider than _coverWidth — the
                          // cascade needs the room the tile already has.
                          : SeriesFanCover(entries: group.entries),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      group.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: colors.secondaryText,
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

/// Loading / error state, in the same centered slot so the page doesn't
/// reflow as it moves between them.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = actionLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                height: 1.6,
                color: colors.secondaryText,
              ),
            ),
            if (label != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onAction,
                child: Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
