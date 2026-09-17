import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';
import 'reading_stats.dart';

/// One reader's year, boiled down to what fits on a shareable card — the
/// stats page's "your year in books" (cactus pro). Pure over the shelf, so
/// the card always agrees with the stats page's own numbers
/// ([ReadingStats]'s rules for books and pages read this year).
class YearInBooks {
  const YearInBooks({
    required this.year,
    required this.books,
    required this.pages,
    required this.finished,
    this.topGenre,
    this.favourite,
    this.longest,
    this.averageRating,
    this.busiestMonth,
  });

  /// At most this many covers go on the card.
  static const maxCovers = 6;

  final int year;
  final int books;
  final int pages;

  /// Books finished this year, most recently finished first, at most
  /// [maxCovers].
  final List<LibraryBook> finished;

  final String? topGenre;

  /// The highest-rated book finished this year (the later finish breaks a
  /// tie). Null when nothing finished this year was rated.
  final LibraryBook? favourite;

  /// The longest book finished this year, when any had a page count.
  final LibraryBook? longest;

  /// Average of this year's ratings.
  final double? averageRating;

  /// 1–12, the month the most books were finished in (the earlier on a
  /// tie). Null with nothing finished.
  final int? busiestMonth;

  bool get isEmpty => books == 0;

  factory YearInBooks.from(Iterable<LibraryBook> shelf, {DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    final thisYear = [
      for (final entry in shelf)
        if (entry.status == ReadingStatus.finished &&
            entry.progress.finishedAt?.toLocal().year == year)
          entry,
    ]..sort((a, b) => b.progress.finishedAt!.compareTo(a.progress.finishedAt!));

    var pages = 0;
    final byMonth = List<int>.filled(12, 0);
    final genres = <String, int>{};
    LibraryBook? favourite;
    LibraryBook? longest;
    var ratingSum = 0.0;
    var rated = 0;
    for (final entry in thisYear) {
      pages += entry.pageCount ?? entry.currentPage;
      byMonth[entry.progress.finishedAt!.toLocal().month - 1]++;
      for (final genre in {
        for (final category in entry.book.categories)
          ?ReadingStats.genreOf(category),
      }) {
        genres[genre] = (genres[genre] ?? 0) + 1;
      }
      if (entry.rating case final rating?) {
        ratingSum += rating;
        rated++;
        // Sorted newest first, so only a strictly higher rating replaces.
        if (favourite == null || rating > favourite.rating!) favourite = entry;
      }
      final length = entry.pageCount;
      if (length != null && length > (longest?.pageCount ?? 0)) {
        longest = entry;
      }
    }

    String? topGenre;
    var topCount = 0;
    for (final MapEntry(key: genre, value: count) in genres.entries) {
      if (count > topCount) {
        topGenre = genre;
        topCount = count;
      }
    }

    int? busiestMonth;
    var busiest = 0;
    for (var month = 0; month < 12; month++) {
      if (byMonth[month] > busiest) {
        busiest = byMonth[month];
        busiestMonth = month + 1;
      }
    }

    return YearInBooks(
      year: year,
      books: thisYear.length,
      pages: pages,
      finished: thisYear.take(maxCovers).toList(),
      topGenre: topGenre,
      favourite: favourite,
      longest: longest,
      averageRating: rated == 0 ? null : ratingSum / rated,
      busiestMonth: busiestMonth,
    );
  }
}
