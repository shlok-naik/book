import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';

/// How fast the reader gets through books — the stats page's "reading
/// speed" section (cactus pro). Pure over the shelf.
///
/// Only books finished this year that also know when they were started
/// count towards speed: a finished book with no start date (most Goodreads
/// imports) says nothing about how long it took. A book started and
/// finished on the same day took one day.
class ReadingSpeed {
  const ReadingSpeed({
    required this.year,
    required this.timedBooks,
    required this.booksThisYear,
    required this.booksLastYear,
    this.averageDays,
    this.pagesPerDay,
    this.fastest,
    this.fastestDays,
  });

  final int year;

  /// Books finished this year with both dates — what the averages use.
  final int timedBooks;

  final int booksThisYear;
  final int booksLastYear;

  /// Mean days from start to finish.
  final double? averageDays;

  /// Pages read per day across the timed books that have a page count.
  final double? pagesPerDay;

  /// The timed book read in the fewest days (the later finish on a tie).
  final LibraryBook? fastest;
  final int? fastestDays;

  bool get hasTimedBooks => timedBooks > 0;

  /// Days from [start] to [finish], counting both — calendar days, so a
  /// late-night start and an early-morning finish is two days, not zero.
  static int daysBetween(DateTime start, DateTime finish) {
    final a = DateTime(start.year, start.month, start.day);
    final b = DateTime(finish.year, finish.month, finish.day);
    final days = b.difference(a).inHours / 24;
    return days < 0 ? 1 : days.round() + 1;
  }

  factory ReadingSpeed.from(Iterable<LibraryBook> books, {DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    var thisYear = 0;
    var lastYear = 0;
    var timed = 0;
    var totalDays = 0;
    var pages = 0;
    var pagedDays = 0;
    LibraryBook? fastest;
    int? fastestDays;

    for (final entry in books) {
      if (entry.status != ReadingStatus.finished) continue;
      final finished = entry.progress.finishedAt?.toLocal();
      if (finished == null) continue;
      if (finished.year == year - 1) lastYear++;
      if (finished.year != year) continue;
      thisYear++;
      final started = entry.progress.startedAt?.toLocal();
      if (started == null) continue;
      final days = daysBetween(started, finished);
      timed++;
      totalDays += days;
      if (entry.pageCount case final count? when count > 0) {
        pages += count;
        pagedDays += days;
      }
      if (fastestDays == null ||
          days < fastestDays ||
          (days == fastestDays &&
              finished.isAfter(fastest!.progress.finishedAt!.toLocal()))) {
        fastest = entry;
        fastestDays = days;
      }
    }

    return ReadingSpeed(
      year: year,
      timedBooks: timed,
      booksThisYear: thisYear,
      booksLastYear: lastYear,
      averageDays: timed == 0 ? null : totalDays / timed,
      pagesPerDay: pagedDays == 0 ? null : pages / pagedDays,
      fastest: fastest,
      fastestDays: fastestDays,
    );
  }
}
