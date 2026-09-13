import '../../goals/domain/reading_goal.dart';
import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';

/// One genre and how many of the reader's books carry it.
typedef GenreCount = ({String genre, int books});

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
  });

  factory ReadingStats.from(Iterable<LibraryBook> books, {DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
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
          if (finishedAt?.year == year) {
            booksThisYear++;
            pagesThisYear += length;
            booksByMonth[finishedAt!.month - 1]++;
            pagesByMonth[finishedAt.month - 1] += length;
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

  /// Progress against [goal], or null without one.
  ReadingGoal? goalProgress(int? goal) => goal == null
      ? null
      : ReadingGoal(goal: goal, finished: booksThisYear, year: year);

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
