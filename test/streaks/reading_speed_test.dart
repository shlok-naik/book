import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/streaks/domain/reading_speed.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryBook _book(
  String title, {
  DateTime? started,
  DateTime? finished,
  int? pages,
  ReadingStatus status = ReadingStatus.finished,
}) => LibraryBook(
  book: Book(
    id: 'b-$title',
    googleBooksId: 'g-$title',
    title: title,
    author: 'someone',
    pageCount: pages,
  ),
  progress: UserBook(
    id: 'u-$title',
    bookId: 'b-$title',
    currentPage: pages ?? 0,
    status: status,
    startedAt: started,
    finishedAt: finished,
  ),
);

void main() {
  final now = DateTime(2026, 9, 17);

  test('counts calendar days, both ends included', () {
    expect(
      ReadingSpeed.daysBetween(
        DateTime(2026, 1, 1, 23),
        DateTime(2026, 1, 2, 1),
      ),
      2,
    );
    expect(
      ReadingSpeed.daysBetween(DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
      1,
    );
  });

  test('averages only books with both dates this year', () {
    final speed = ReadingSpeed.from([
      _book(
        'Dune',
        started: DateTime(2026, 3, 1),
        finished: DateTime(2026, 3, 10),
        pages: 400,
      ),
      _book(
        'Circe',
        started: DateTime(2026, 4, 1),
        finished: DateTime(2026, 4, 2),
        pages: 200,
      ),
      _book('Imported', finished: DateTime(2026, 5, 1), pages: 300),
      _book(
        'Old',
        started: DateTime(2025, 1, 1),
        finished: DateTime(2025, 1, 5),
      ),
      _book(
        'Reading',
        started: DateTime(2026, 9, 1),
        status: ReadingStatus.reading,
      ),
    ], now: now);

    expect(speed.booksThisYear, 3);
    expect(speed.booksLastYear, 1);
    expect(speed.timedBooks, 2);
    expect(speed.averageDays, 6); // (10 + 2) / 2
    expect(speed.pagesPerDay, closeTo(600 / 12, 0.001));
    expect(speed.fastest?.book.title, 'Circe');
    expect(speed.fastestDays, 2);
  });

  test('nothing timed means no averages', () {
    final speed = ReadingSpeed.from([
      _book('Imported', finished: DateTime(2026, 5, 1)),
    ], now: now);
    expect(speed.hasTimedBooks, isFalse);
    expect(speed.averageDays, isNull);
    expect(speed.pagesPerDay, isNull);
  });
}
