import 'book_edition.dart';
import 'collections.dart';
import 'library_book.dart';
import 'user_book.dart';

/// The rules for what happens to a book when it changes shelf, and how a
/// shelf section is ordered — in one place, so moving a book on the
/// library page (drag, keyboard or screen-reader action),
/// `move <book> <shelf>` on the add tab, and `finish <book>` can't drift
/// apart.
///
/// Pure functions over domain values, no I/O: `LibraryController` applies
/// the result optimistically and persists it.
abstract final class ShelfRules {
  /// [entry]'s progress row as it should look once it lands on [target].
  ///
  /// * **to read** / **reading** — back to page 0 (0%). A queued book
  ///   hasn't been opened; a book moved (back) into "reading" by hand is
  ///   being started over, not resumed mid-way from a stale page.
  /// * **finished** — 100%: the page jumps to the last page when the page
  ///   count is known. Without one, `LibraryBook.completion` already reads
  ///   a finished book as 1.0, so the bar is full either way.
  /// * **did not finish** — progress is kept. How far a reader got before
  ///   giving up is exactly the thing worth remembering about a DNF.
  ///
  /// Moving anywhere but "finished" clears `finishedAt`, so the column
  /// never claims a finish date for a book that isn't finished. The rating
  /// is left alone (see `LibraryBook.rating`). The manual shelf position is
  /// cleared: an index from the old section means nothing in the new one,
  /// which mirrors what the `touch_updated_at` trigger does server-side.
  ///
  /// Returns [entry]'s own progress unchanged when [target] is the shelf it
  /// is already on — that is a reorder, not a move, and must not wipe a
  /// reading book's page.
  static UserBook enter(
    LibraryBook entry,
    ReadingStatus target, {
    DateTime? at,
  }) {
    final progress = entry.progress;
    if (progress.status == target) return progress;

    return switch (target) {
      ReadingStatus.toBeRead || ReadingStatus.reading => progress.copyWith(
        status: target,
        currentPage: 0,
        clearFinishedAt: true,
        clearShelfPosition: true,
      ),
      ReadingStatus.finished => progress.copyWith(
        status: target,
        currentPage: entry.pageCount ?? progress.currentPage,
        finishedAt: (at ?? DateTime.now()).toUtc(),
        clearShelfPosition: true,
      ),
      ReadingStatus.dnf => progress.copyWith(
        status: target,
        clearFinishedAt: true,
        clearShelfPosition: true,
      ),
    };
  }

  /// The page [entry] should be on once [edition] becomes the copy the
  /// reader owns (null: back to no edition, so the work's own length).
  ///
  /// The reader's *place in the book* is what's kept, not the number:
  /// page 548 of a 703-page printing is page 498 of a 639-page one —
  /// both 78%. So:
  ///
  /// * a finished book stays at the last page of whichever copy;
  /// * page 0 stays page 0;
  /// * with both lengths known, the page scales proportionally;
  /// * with only the new length known, the page is kept;
  /// * either way, a book that isn't finished never lands *on* the last
  ///   page, which would read as 100% without anyone finishing it;
  /// * with no new length, the page is kept as is.
  static int pageForEdition(LibraryBook entry, BookEdition? edition) {
    final current = entry.currentPage;
    final newTotal = edition?.pageCount ?? entry.book.pageCount;
    if (entry.isFinished) return newTotal ?? current;
    if (current == 0 || newTotal == null) return current;

    final oldTotal = entry.pageCount;
    final scaled = oldTotal != null && oldTotal > 0
        ? (current / oldTotal * newTotal).round()
        : current;
    // Not finished, so never on the last page — that would read as 100%.
    return scaled.clamp(0, newTotal > 0 ? newTotal - 1 : 0);
  }

  /// [entry]'s progress row once it lands on [target] — built-in *or*
  /// custom shelf. The one rule every move uses.
  ///
  /// * **onto a custom shelf** — only `shelfId` changes (and the manual
  ///   position resets). Status, page, finish date and rating are kept: a
  ///   custom shelf is a place, not a reading state, so moving a half-read
  ///   book to "summer" must not start it over.
  /// * **onto a built-in shelf from a custom one** — the custom shelf is
  ///   cleared; if the status also changes, [enter]'s side effects apply,
  ///   and if it doesn't (a reading book moved back to "reading") the
  ///   progress is kept, exactly as a reorder would keep it.
  /// * **onto a built-in shelf from a built-in one** — [enter].
  ///
  /// Returns [entry]'s own progress unchanged when it is already on
  /// [target].
  static UserBook enterShelf(
    LibraryBook entry,
    ShelfRef target, {
    DateTime? at,
  }) {
    final progress = entry.progress;
    switch (target) {
      case CustomShelfRef(:final shelfId):
        if (progress.shelfId == shelfId) return progress;
        return progress.copyWith(shelfId: shelfId, clearShelfPosition: true);
      case StatusShelfRef(:final status):
        if (progress.shelfId == null) return enter(entry, status, at: at);
        final offCustom = progress.copyWith(
          clearShelfId: true,
          clearShelfPosition: true,
        );
        if (progress.status == status) return offCustom;
        return enter(entry.copyWith(progress: offCustom), status, at: at);
    }
  }

  /// Orders one section for display.
  ///
  /// [entries] arrive in the shelf's natural order — most recently updated
  /// first, as `UserBookRepository.fetchLibrary` returns it. Books never
  /// placed by hand (null position) keep that order and come first, so a
  /// book that just arrived on this shelf shows at the top the way it
  /// always has. Books the reader *has* placed follow, in their chosen
  /// order. The sort is stable, so ties keep the natural order.
  static List<LibraryBook> sortSection(Iterable<LibraryBook> entries) {
    final unplaced = <LibraryBook>[];
    final placed = <LibraryBook>[];
    for (final entry in entries) {
      (entry.progress.shelfPosition == null ? unplaced : placed).add(entry);
    }
    _stableSortByPosition(placed);
    return [...unplaced, ...placed];
  }

  /// `List.sort` isn't guaranteed stable, so sort indices instead and
  /// break ties on the original index.
  static void _stableSortByPosition(List<LibraryBook> entries) {
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
    indexed.sort((a, b) {
      final byPosition = a.$2.progress.shelfPosition!.compareTo(
        b.$2.progress.shelfPosition!,
      );
      return byPosition != 0 ? byPosition : a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < indexed.length; i++) {
      entries[i] = indexed[i].$2;
    }
  }

  /// The section's order after [moved] is dropped at [index] — ids only,
  /// ready for `UserBookRepository.saveShelfOrder`. [section] is the
  /// target section as currently displayed, and may or may not already
  /// contain [moved] (a reorder within a section vs a move into it).
  /// [index] is clamped, so a drop past the end appends.
  static List<String> orderAfterDrop(
    List<LibraryBook> section,
    String moved,
    int index,
  ) {
    final ids = [for (final entry in section) entry.id];
    final from = ids.indexOf(moved);
    if (from != -1) {
      ids.removeAt(from);
      // Dropping "before the tile after me" within the same section means
      // the list already shifted left by one once I was removed.
      if (from < index) index -= 1;
    }
    ids.insert(index.clamp(0, ids.length), moved);
    return ids;
  }
}
