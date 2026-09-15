import '../../goals/domain/reading_goal.dart';
import '../../library/domain/book_note.dart';
import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';

/// One genre and how many of the reader's books carry it.
typedef GenreCount = ({String genre, int books});

/// One of the reader's tags and how many books on the shelf carry it.
typedef TagCount = ({String tag, int books});

/// Everything the stats page shows about the shelf itself, computed from
/// the books `LibraryController` already holds — no extra query, and so
/// always in step with the shelf. Free on every plan.
///
/// The rules, so every surface agrees:
/// * **books read** — books on the finished shelf. "This year" means a
///   `finishedAt` in the current local year; a finished book with no date
///   (a Goodreads import without "Date Read") counts all-time only.
/// * **pages read** — a finished book counts its full length (the owned
///   edition's, when there is one); a book being read or dropped counts up
///   to the reader's page; a to-read book counts nothing. This year's
///   pages are only the full lengths of books finished this year, since
///   the shelf doesn't know when an in-progress page was reached.
/// * **genres** — across every book that isn't just queued, each book
///   counted once per genre. See [genreOf] for how Google's categories
///   become one.
/// * **imports** — a book a Goodreads import brought in
///   (`UserBook.imported`) is history, not reading done in cactus. Unless it
///   was finished again after the import, it stays out of [booksByMonth] and
///   [pagesByMonth]. If the import ([importedAt]) happened this year, the
///   imported books finished this year before it become the pace chart's
///   [paceBaseline], and [finishesAfterBaseline] is what pace counts from
///   there. Book and page totals, shelf counts and genres still include
///   imported books — they describe the library, not the months.
class ReadingStats {
  const ReadingStats({
    required this.year,
    required this.booksThisYear,
    required this.booksAllTime,
    required this.pagesThisYear,
    required this.pagesAllTime,
    required this.reading,
    required this.toRead,
    required this.didNotFinish,
    required this.averageRating,
    required this.genres,
    required this.booksByMonth,
    required this.pagesByMonth,
    this.paceBaseline,
    this.finishesAfterBaseline = const [],
  });

  static ({
    List<LibraryBook> books,
    DateTime? importedAt,
    int year,
    ReadingStats stats,
  })?
  _lastForShelf;

  /// [ReadingStats.from] for the live shelf, computed once per shelf change
  /// instead of on every rebuild of every page that shows a number from it
  /// (the add tab's goal, the whole stats page).
  ///
  /// Keyed on the list's *identity*: `LibraryController.books` hands out the
  /// same list until the shelf changes, and a new one after. Also keyed on
  /// the year, so a page left open over New Year's doesn't keep counting
  /// the old one.
  static ReadingStats forShelf(
    List<LibraryBook> books, {
    DateTime? importedAt,
  }) {
    final year = DateTime.now().year;
    final last = _lastForShelf;
    if (last != null &&
        identical(last.books, books) &&
        last.importedAt == importedAt &&
        last.year == year) {
      return last.stats;
    }
    final stats = ReadingStats.from(books, importedAt: importedAt);
    _lastForShelf = (
      books: books,
      importedAt: importedAt,
      year: year,
      stats: stats,
    );
    return stats;
  }

  factory ReadingStats.from(
    Iterable<LibraryBook> books, {
    DateTime? now,
    DateTime? importedAt,
  }) {
    final year = (now ?? DateTime.now()).year;
    final importLocal = importedAt?.toLocal();
    final baselineThisYear = importLocal != null && importLocal.year == year;
    var baselineBooks = 0;
    final afterBaseline = <DateTime>[];
    var booksThisYear = 0;
    var booksAllTime = 0;
    var pagesThisYear = 0;
    var pagesAllTime = 0;
    var reading = 0;
    var toRead = 0;
    var dnf = 0;
    var ratingSum = 0.0;
    var rated = 0;
    final genreCounts = <String, int>{};
    final booksByMonth = List<int>.filled(12, 0);
    final pagesByMonth = List<int>.filled(12, 0);

    for (final entry in books) {
      switch (entry.status) {
        case ReadingStatus.finished:
          booksAllTime++;
          final length = entry.pageCount ?? entry.currentPage;
          pagesAllTime += length;
          final finishedAt = entry.progress.finishedAt?.toLocal();
          // Imported history: finished at or before the import (or with no
          // import date known at all).
          final importedHistory =
              entry.progress.imported &&
              (importLocal == null ||
                  finishedAt == null ||
                  !finishedAt.isAfter(importLocal));
          if (finishedAt?.year == year) {
            booksThisYear++;
            pagesThisYear += length;
            if (!importedHistory) {
              booksByMonth[finishedAt!.month - 1]++;
              pagesByMonth[finishedAt.month - 1] += length;
            }
            if (baselineThisYear) {
              if (!finishedAt!.isAfter(importLocal)) {
                // Everything finished this year before the import — imported
                // or not — is where pace starts from.
                baselineBooks++;
              } else {
                afterBaseline.add(finishedAt);
              }
            }
          }
          if (entry.rating case final rating?) {
            ratingSum += rating;
            rated++;
          }
        case ReadingStatus.reading:
          reading++;
          pagesAllTime += entry.currentPage;
        case ReadingStatus.dnf:
          dnf++;
          pagesAllTime += entry.currentPage;
        case ReadingStatus.toBeRead:
          toRead++;
      }

      if (entry.status == ReadingStatus.toBeRead) continue;
      final genres = {
        for (final category in entry.book.categories) ?genreOf(category),
      };
      for (final genre in genres) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }

    final genres =
        [
          for (final MapEntry(key: genre, value: count) in genreCounts.entries)
            (genre: genre, books: count),
        ]..sort((a, b) {
          final byCount = b.books.compareTo(a.books);
          return byCount != 0 ? byCount : a.genre.compareTo(b.genre);
        });

    return ReadingStats(
      year: year,
      booksThisYear: booksThisYear,
      booksAllTime: booksAllTime,
      pagesThisYear: pagesThisYear,
      pagesAllTime: pagesAllTime,
      reading: reading,
      toRead: toRead,
      didNotFinish: dnf,
      averageRating: rated == 0 ? null : ratingSum / rated,
      genres: List.unmodifiable(genres),
      booksByMonth: List.unmodifiable(booksByMonth),
      pagesByMonth: List.unmodifiable(pagesByMonth),
      paceBaseline: baselineThisYear
          ? PaceBaseline(at: importedAt!, books: baselineBooks)
          : null,
      finishesAfterBaseline: List.unmodifiable(afterBaseline..sort()),
    );
  }

  final int year;
  final int booksThisYear;
  final int booksAllTime;
  final int pagesThisYear;
  final int pagesAllTime;
  final int reading;
  final int toRead;
  final int didNotFinish;

  /// Mean of the reader's own ratings on finished books; null when none.
  final double? averageRating;

  /// Most common first; ties alphabetical.
  final List<GenreCount> genres;

  /// Books finished in [year], one count per calendar month, index 0 = Jan
  /// — the stats page's monthly activity chart.
  final List<int> booksByMonth;

  /// Same shape as [booksByMonth], but each finished book's full length.
  final List<int> pagesByMonth;

  /// Set when the library was imported during [year] — see the class doc.
  final PaceBaseline? paceBaseline;

  /// With a [paceBaseline]: each book finished this year after the import,
  /// oldest first (local time). Empty otherwise.
  final List<DateTime> finishesAfterBaseline;

  /// How many books carry each tag — the stats page's "tags" section.
  ///
  /// [tags] is every `book_tags` row (`BookNotesRepository.fetchAllTags`),
  /// which is fetched separately from the shelf and so can be momentarily
  /// out of step with it; only rows whose book is still in [books] count,
  /// so a just-deleted book never inflates a tag. Tags compare the way the
  /// database's unique index does ([BookTag.normalize]) and each book
  /// counts once per tag; the label shown is the spelling most recently
  /// applied. Most books first; ties alphabetical.
  static List<TagCount> tagCounts(
    Iterable<BookTag> tags,
    Iterable<LibraryBook> books,
  ) {
    final onShelf = {for (final entry in books) entry.id};
    final booksByTag = <String, Set<String>>{};
    final labels = <String, ({String label, DateTime at})>{};
    for (final tag in tags) {
      if (!onShelf.contains(tag.userBookId)) continue;
      final key = BookTag.normalize(tag.tag);
      if (key.isEmpty) continue;
      (booksByTag[key] ??= {}).add(tag.userBookId);
      final existing = labels[key];
      if (existing == null || tag.createdAt.isAfter(existing.at)) {
        labels[key] = (label: tag.tag.trim(), at: tag.createdAt);
      }
    }
    return [
      for (final MapEntry(key: key, value: ids) in booksByTag.entries)
        (tag: labels[key]!.label, books: ids.length),
    ]..sort((a, b) {
      final byCount = b.books.compareTo(a.books);
      return byCount != 0
          ? byCount
          : a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
    });
  }

  /// Progress against [goal], or null without one. Pace is measured from
  /// the [paceBaseline] when there is one.
  ReadingGoal? goalProgress(int? goal) => goal == null
      ? null
      : ReadingGoal(
          goal: goal,
          finished: booksThisYear,
          year: year,
          baseline: paceBaseline,
        );

  /// Categories too broad to say anything about a reader's taste on their
  /// own — "Fiction / Science Fiction" is science fiction, not fiction.
  static const _umbrellas = {
    'fiction',
    'juvenile fiction',
    'young adult fiction',
    'juvenile nonfiction',
    'young adult nonfiction',
    'general',
  };

  /// Turns one Google Books category into a short, lowercase genre, or
  /// null when it says nothing. Google categories are either one word
  /// ("Fiction") or a BISAC path ("Fiction / Science Fiction / Space
  /// Opera"); the first specific segment is the genre, so both "Fiction /
  /// Science Fiction / General" and "Science Fiction" become
  /// "science fiction", and a bare "Fiction" becomes "fiction" only when
  /// there's nothing more specific to say.
  static String? genreOf(String category) {
    final segments = [
      for (final segment in category.split('/'))
        if (segment.trim().toLowerCase() case final s when s.isNotEmpty) s,
    ];
    if (segments.isEmpty) return null;
    for (final segment in segments) {
      if (!_umbrellas.contains(segment)) return segment;
    }
    final first = segments.first;
    return first == 'general' ? null : first;
  }
}
