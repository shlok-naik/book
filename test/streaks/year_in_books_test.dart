import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/streaks/domain/year_in_books.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryBook _book(
  String title,
  ReadingStatus status, {
  int? pages,
  DateTime? finishedAt,
  double? rating,
  List<String> categories = const [],
}) => LibraryBook(
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
    currentPage: pages ?? 0,
    status: status,
    finishedAt: finishedAt,
    rating: rating,
  ),
);

void main() {
  final now = DateTime(2026, 9, 17);

  test('sums only books finished this year', () {
    final year = YearInBooks.from([
      _book(
        'Dune',
        ReadingStatus.finished,
        pages: 412,
        finishedAt: DateTime(2026, 3, 4),
        rating: 5,
        categories: ['Fiction / Science Fiction / General'],
      ),
      _book(
        'Circe',
        ReadingStatus.finished,
        pages: 393,
        finishedAt: DateTime(2026, 3, 20),
        rating: 4,
        categories: ['Fiction / Fantasy / General'],
      ),
      _book(
        'Emma',
        ReadingStatus.finished,
        pages: 900,
        finishedAt: DateTime(2025, 12, 30),
        rating: 5,
      ),
      _book('Middlemarch', ReadingStatus.reading, pages: 800),
      _book(
        'Beloved',
        ReadingStatus.finished,
        pages: 324,
        finishedAt: DateTime(2026, 8, 1),
        categories: ['Fiction / Science Fiction / Hard'],
      ),
    ], now: now);

    expect(year.year, 2026);
    expect(year.books, 3);
    expect(year.pages, 412 + 393 + 324);
    expect(
      [for (final b in year.finished) b.book.title],
      ['Beloved', 'Circe', 'Dune'],
    );
    expect(year.favourite?.book.title, 'Dune');
    expect(year.longest?.book.title, 'Dune');
    expect(year.averageRating, 4.5);
    expect(year.busiestMonth, 3);
    expect(year.topGenre, isNotNull);
  });

  test('a later finish wins a rating tie', () {
    final year = YearInBooks.from([
      _book(
        'A',
        ReadingStatus.finished,
        finishedAt: DateTime(2026, 1, 1),
        rating: 4,
      ),
      _book(
        'B',
        ReadingStatus.finished,
        finishedAt: DateTime(2026, 5, 1),
        rating: 4,
      ),
    ], now: now);
    expect(year.favourite?.book.title, 'B');
  });

  test('an empty year is empty', () {
    final year = YearInBooks.from(const [], now: now);
    expect(year.isEmpty, isTrue);
    expect(year.busiestMonth, isNull);
    expect(year.favourite, isNull);
  });

  test('keeps at most six covers', () {
    final year = YearInBooks.from([
      for (var i = 1; i <= 9; i++)
        _book(
          'Book $i',
          ReadingStatus.finished,
          finishedAt: DateTime(2026, 1, i),
        ),
    ], now: now);
    expect(year.books, 9);
    expect(year.finished, hasLength(YearInBooks.maxCovers));
    expect(year.finished.first.book.title, 'Book 9');
  });
}
