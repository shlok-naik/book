import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/shelf_rules.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:flutter_test/flutter_test.dart';

const _dune = Book(
  id: 'b1',
  googleBooksId: 'g1',
  title: 'Dune',
  author: 'Frank Herbert',
  pageCount: 400,
);

const _noPages = Book(id: 'b2', googleBooksId: 'g2', title: 'X', author: 'Y');

LibraryBook _entry(
  String id,
  ReadingStatus status, {
  int page = 0,
  double? position,
  Book book = _dune,
  DateTime? finishedAt,
  double? rating,
}) => LibraryBook(
  book: book,
  progress: UserBook(
    id: id,
    bookId: book.id,
    currentPage: page,
    status: status,
    shelfPosition: position,
    finishedAt: finishedAt,
    rating: rating,
  ),
);

void main() {
  group('ShelfRules.enter', () {
    test('moving into reading stamps the start date; to read does not', () {
      final at = DateTime.utc(2026, 9, 1);
      final started = ShelfRules.enter(
        _entry('a', ReadingStatus.toBeRead),
        ReadingStatus.reading,
        at: at,
      );
      expect(started.startedAt, at);

      final queued = ShelfRules.enter(
        _entry('a', ReadingStatus.reading),
        ReadingStatus.toBeRead,
        at: at,
      );
      expect(queued.startedAt, isNull);
    });

    test('to read and reading reset progress to page 0', () {
      for (final target in [ReadingStatus.toBeRead, ReadingStatus.reading]) {
        final from = target == ReadingStatus.reading
            ? ReadingStatus.finished
            : ReadingStatus.reading;
        final moved = ShelfRules.enter(
          _entry('a', from, page: 250, finishedAt: DateTime(2026)),
          target,
        );
        expect(moved.status, target);
        expect(moved.currentPage, 0);
        expect(moved.finishedAt, isNull);
      }
    });

    test('finished jumps to the last page and stamps a finish date', () {
      final at = DateTime.utc(2026, 9, 1);
      final moved = ShelfRules.enter(
        _entry('a', ReadingStatus.toBeRead, page: 12),
        ReadingStatus.finished,
        at: at,
      );
      expect(moved.currentPage, 400);
      expect(moved.finishedAt, at);
      expect(
        LibraryBook(book: _dune, progress: moved).completion,
        1,
        reason: '100% completion',
      );
    });

    test('finished without a page count keeps the page, still 100%', () {
      final entry = _entry(
        'a',
        ReadingStatus.reading,
        page: 80,
        book: _noPages,
      );
      final moved = ShelfRules.enter(entry, ReadingStatus.finished);
      expect(moved.currentPage, 80);
      expect(LibraryBook(book: _noPages, progress: moved).completion, 1);
    });

    test('dnf keeps the page reached and clears any finish date', () {
      final moved = ShelfRules.enter(
        _entry(
          'a',
          ReadingStatus.finished,
          page: 400,
          finishedAt: DateTime(2026),
        ),
        ReadingStatus.dnf,
      );
      expect(moved.currentPage, 400);
      expect(moved.finishedAt, isNull);
    });

    test('keeps the rating and clears the manual position on any move', () {
      final moved = ShelfRules.enter(
        _entry('a', ReadingStatus.finished, position: 3, rating: 4.5),
        ReadingStatus.reading,
      );
      expect(moved.rating, 4.5);
      expect(moved.shelfPosition, isNull);
    });

    test('the shelf a book is already on is not a move', () {
      final entry = _entry('a', ReadingStatus.reading, page: 120, position: 2);
      expect(
        ShelfRules.enter(entry, ReadingStatus.reading),
        same(entry.progress),
      );
    });
  });

  group('ShelfRules.pageForEdition', () {
    BookEdition edition(int? pages) => BookEdition(
      id: 'e',
      googleBooksId: 'g',
      title: 'Dune',
      author: 'Frank Herbert',
      format: EditionFormat.physical,
      pageCount: pages,
    );

    test('keeps the reader at the same percentage', () {
      // 548 of 703 = 78%, which is page 493 of a 639-page copy.
      const doctorSleep = Book(
        id: 'b',
        googleBooksId: 'g',
        title: 'Doctor Sleep',
        author: 'Stephen King',
        pageCount: 703,
      );
      final entry = _entry(
        'a',
        ReadingStatus.reading,
        page: 548,
        book: doctorSleep,
      );
      expect(ShelfRules.pageForEdition(entry, edition(639)), 498);
    });

    test('an unfinished book never rescales onto the last page', () {
      final entry = _entry('a', ReadingStatus.reading, page: 399);
      expect(ShelfRules.pageForEdition(entry, edition(200)), 199);
    });

    test('a finished book lands on the new last page', () {
      final entry = _entry('a', ReadingStatus.finished, page: 400);
      expect(ShelfRules.pageForEdition(entry, edition(250)), 250);
    });

    test('page 0 stays 0, and no new length keeps the page', () {
      expect(
        ShelfRules.pageForEdition(
          _entry('a', ReadingStatus.toBeRead),
          edition(250),
        ),
        0,
      );
      expect(
        ShelfRules.pageForEdition(
          _entry('a', ReadingStatus.reading, page: 42, book: _noPages),
          edition(null),
        ),
        42,
      );
    });

    test('without an old length the page is kept but clamped', () {
      final entry = _entry('a', ReadingStatus.dnf, page: 300, book: _noPages);
      expect(ShelfRules.pageForEdition(entry, edition(250)), 249);
    });
  });

  group('ShelfRules.sortSection', () {
    test('unplaced books first in natural order, then placed by position', () {
      final sorted = ShelfRules.sortSection([
        _entry('placed-2', ReadingStatus.reading, position: 2),
        _entry('new-1', ReadingStatus.reading),
        _entry('placed-0', ReadingStatus.reading, position: 0),
        _entry('new-2', ReadingStatus.reading),
      ]);
      expect(sorted.map((e) => e.id), [
        'new-1',
        'new-2',
        'placed-0',
        'placed-2',
      ]);
    });

    test('is stable for equal positions', () {
      final sorted = ShelfRules.sortSection([
        _entry('first', ReadingStatus.reading, position: 1),
        _entry('second', ReadingStatus.reading, position: 1),
      ]);
      expect(sorted.map((e) => e.id), ['first', 'second']);
    });
  });

  group('ShelfRules.orderAfterDrop', () {
    final section = [
      _entry('a', ReadingStatus.reading),
      _entry('b', ReadingStatus.reading),
      _entry('c', ReadingStatus.reading),
    ];

    test('inserts a book from another section at the index', () {
      expect(ShelfRules.orderAfterDrop(section, 'x', 1), ['a', 'x', 'b', 'c']);
    });

    test('moving up within the section', () {
      expect(ShelfRules.orderAfterDrop(section, 'c', 0), ['c', 'a', 'b']);
    });

    test('moving down accounts for the slot it left', () {
      // "before c" (index 2) with a removed first: lands between b and c.
      expect(ShelfRules.orderAfterDrop(section, 'a', 2), ['b', 'a', 'c']);
      // "after c" (index 3): last.
      expect(ShelfRules.orderAfterDrop(section, 'a', 3), ['b', 'c', 'a']);
    });

    test('clamps an out-of-range index', () {
      expect(ShelfRules.orderAfterDrop(section, 'x', 99), ['a', 'b', 'c', 'x']);
      expect(ShelfRules.orderAfterDrop(section, 'x', -5), ['x', 'a', 'b', 'c']);
    });

    test('into an empty section', () {
      expect(ShelfRules.orderAfterDrop(const [], 'x', 0), ['x']);
    });
  });
}
