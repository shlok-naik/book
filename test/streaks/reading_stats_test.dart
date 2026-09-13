import 'package:book/features/goals/domain/reading_goal.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/streaks/domain/reading_stats.dart';
import 'package:book/features/streaks/domain/streak_math.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryBook _book(
  String title,
  ReadingStatus status, {
  int? pages,
  int page = 0,
  DateTime? finishedAt,
  double? rating,
  List<String> categories = const [],
}) {
  return LibraryBook(
    book: Book(
      id: 'b-$title',
      googleBooksId: 'g-$title',
      title: title,
      author: 'someone',
      pageCount: pages,
      categories: categories,
    ),
    progress: UserBook(
      id: 'u-$title',
      bookId: 'b-$title',
      currentPage: page,
      status: status,
      finishedAt: finishedAt,
      rating: rating,
    ),
  );
}

void main() {
  final now = DateTime(2026, 7, 2, 12);

  group('ReadingStats', () {
    test('counts books and pages by the documented rules', () {
      final stats = ReadingStats.from([
        _book(
          'Dune',
          ReadingStatus.finished,
          pages: 400,
          page: 400,
          finishedAt: DateTime(2026, 3, 1),
          rating: 5,
        ),
        _book(
          'Old',
          ReadingStatus.finished,
          pages: 200,
          page: 200,
          finishedAt: DateTime(2025, 3, 1),
          rating: 4,
        ),
        // Finished with no date (an import without "Date Read"): all time.
        _book('Undated', ReadingStatus.finished, pages: 100, page: 100),
        _book('Reading', ReadingStatus.reading, pages: 300, page: 120),
        _book('Dropped', ReadingStatus.dnf, pages: 500, page: 50),
        _book('Queued', ReadingStatus.toBeRead, pages: 900),
      ], now: now);

      expect(stats.year, 2026);
      expect(stats.booksThisYear, 1);
      expect(stats.booksAllTime, 3);
      expect(stats.pagesThisYear, 400);
      expect(stats.pagesAllTime, 400 + 200 + 100 + 120 + 50);
      expect(stats.reading, 1);
      expect(stats.toRead, 1);
      expect(stats.didNotFinish, 1);
      expect(stats.averageRating, 4.5);
    });

    test('a finished book without a page count counts the page it is on', () {
      final stats = ReadingStats.from([
        _book(
          'Short',
          ReadingStatus.finished,
          page: 90,
          finishedAt: DateTime(2026, 1, 5),
        ),
      ], now: now);
      expect(stats.pagesAllTime, 90);
      expect(stats.averageRating, isNull);
    });

    test('genres: specific over umbrella, once per book, queued books '
        'ignored, most common first', () {
      final stats = ReadingStats.from([
        _book(
          'A',
          ReadingStatus.finished,
          categories: [
            'Fiction / Science Fiction / Space Opera',
            'Science Fiction',
          ],
        ),
        _book('B', ReadingStatus.reading, categories: ['Science Fiction']),
        _book('C', ReadingStatus.dnf, categories: ['Fiction / Fantasy']),
        _book('D', ReadingStatus.toBeRead, categories: ['Romance']),
        _book('E', ReadingStatus.finished, categories: ['Fiction']),
      ], now: now);

      expect(stats.genres, [
        (genre: 'science fiction', books: 2),
        (genre: 'fantasy', books: 1),
        (genre: 'fiction', books: 1),
      ]);
    });

    test('genreOf', () {
      expect(ReadingStats.genreOf('Fiction'), 'fiction');
      expect(ReadingStats.genreOf('Fiction / General'), 'fiction');
      expect(
        ReadingStats.genreOf('Biography & Autobiography / Personal Memoirs'),
        'biography & autobiography',
      );
      expect(ReadingStats.genreOf('General'), isNull);
      expect(ReadingStats.genreOf('  '), isNull);
    });

    test('goal progress uses books finished this year', () {
      final stats = ReadingStats.from([
        _book('A', ReadingStatus.finished, finishedAt: DateTime(2026, 2, 1)),
      ], now: now);
      expect(stats.goalProgress(null), isNull);
      final goal = stats.goalProgress(12)!;
      expect(goal.finished, 1);
      expect(goal.summary, '1 of 12 books in 2026');
    });
  });

  group('ReadingGoal', () {
    test('pace against a steady year', () {
      const goal = ReadingGoal(goal: 12, finished: 6, year: 2026);
      // Roughly half the year gone: six books is on track.
      expect(goal.paceLabel(DateTime(2026, 7, 3)), 'on track');
      expect(goal.paceLabel(DateTime(2026, 3, 1)), '5 ahead');
      expect(goal.paceLabel(DateTime(2026, 12, 31)), '5 behind');
      expect(goal.fraction, 0.5);
      expect(goal.remaining, 6);
    });

    test('past the goal is complete and the bar stays full', () {
      const goal = ReadingGoal(goal: 2, finished: 3, year: 2026);
      expect(goal.isComplete, isTrue);
      expect(goal.fraction, 1);
      expect(goal.remaining, 0);
      expect(goal.paceLabel(DateTime(2026, 2)), 'goal reached');
    });

    test('valid range', () {
      expect(ReadingGoal.isValid(0), isFalse);
      expect(ReadingGoal.isValid(1), isTrue);
      expect(ReadingGoal.isValid(1000), isTrue);
      expect(ReadingGoal.isValid(1001), isFalse);
    });
  });

  group('StreakMath', () {
    final today = DateTime(2026, 3, 29);
    DateTime day(int offset) =>
        DateTime(today.year, today.month, today.day - offset);

    test('current streak ends today or yesterday', () {
      expect(StreakMath.current({day(0), day(1), day(2)}, now: today), 3);
      expect(StreakMath.current({day(1), day(2)}, now: today), 2);
      expect(StreakMath.current({day(2), day(3)}, now: today), 0);
      expect(StreakMath.current({}, now: today), 0);
    });

    test('longest run anywhere, across a month boundary', () {
      final days = {
        DateTime(2026, 2, 27),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 10),
      };
      expect(StreakMath.longest(days), 3);
      expect(StreakMath.longest({}), 0);
    });
  });
}
