import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_series_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_series.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/library_search.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(String id, String title, {String? series, double? position}) => Book(
  id: id,
  googleBooksId: 'g-$id',
  title: title,
  author: 'Frank Herbert',
  pageCount: 300,
  seriesId: series == null ? null : 'series-${series.toLowerCase()}',
  seriesName: series,
  seriesPosition: position,
);

LibraryBook _entry(Book book, ReadingStatus status) => LibraryBook(
  book: book,
  progress: UserBook(
    id: 'u-${book.id}',
    bookId: book.id,
    currentPage: 0,
    status: status,
  ),
);

final _dune = _book('1', 'Dune', series: 'Dune', position: 1);
final _messiah = _book('2', 'Dune Messiah', series: 'Dune', position: 2);
final _children = _book('3', 'Children of Dune', series: 'Dune', position: 3);
final _novella = _book('4', 'Dune: A Novella', series: 'Dune');

class _FakeSeries extends BookSeriesRepository {
  _FakeSeries({this.catalogue = const [], this.failure});

  final List<Book> catalogue;
  final LibraryException? failure;
  final calls = <(String, String, double?)>[];

  @override
  Future<Book> setSeries(
    String bookId,
    String seriesName, {
    double? position,
  }) async {
    if (failure != null) throw failure!;
    calls.add((bookId, seriesName, position));
    final base = catalogue.firstWhere(
      (book) => book.id == bookId,
      orElse: () => _book(bookId, 'unknown'),
    );
    return base.withSeries(
      seriesId: 'series-${seriesName.toLowerCase()}',
      seriesName: seriesName,
      seriesPosition: position,
    );
  }

  @override
  Future<BookSeries?> findByName(String name) async {
    for (final book in catalogue) {
      if (book.seriesName != null &&
          book.seriesName!.toLowerCase() == name.trim().toLowerCase()) {
        return BookSeries(id: book.seriesId!, name: book.seriesName!);
      }
    }
    return null;
  }

  @override
  Future<List<Book>> booksInSeries(String seriesId) async =>
      BookSeries.sortBooks(
        catalogue.where((book) => book.seriesId == seriesId),
      );
}

class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;
  final started = <String>[];
  final moved = <ReadingStatus>[];

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<StartOutcome> start(String bookId) async {
    started.add(bookId);
    return StartOutcome(
      UserBook(
        id: 'u-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: ReadingStatus.reading,
      ),
      alreadyExists: false,
    );
  }

  @override
  Future<UserBook> changeShelf(UserBook updated) async {
    moved.add(updated.status);
    return updated;
  }
}

class _Events extends ReadingEventRepository {
  final logged = <ReadingEventType>[];

  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async => logged.add(type);
}

class _NoCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
}

Future<(LibraryController, _Shelf)> _controller(
  List<LibraryBook> rows,
  _FakeSeries series,
) async {
  final shelf = _Shelf(rows);
  final controller = LibraryController(
    lookup: BookLookupService(
      cache: _NoCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
    ),
    userBooks: shelf,
    events: _Events(),
    series: series,
  );
  await controller.load();
  return (controller, shelf);
}

void main() {
  group('BookSeries', () {
    test('sorts numbered books by number, unnumbered after by title', () {
      expect(
        BookSeries.sortBooks([
          _novella,
          _children,
          _dune,
          _messiah,
        ]).map((b) => b.title),
        ['Dune', 'Dune Messiah', 'Children of Dune', 'Dune: A Novella'],
      );
    });

    test('next to read skips finished and dropped books', () {
      final shelf = {
        _dune.id: _entry(_dune, ReadingStatus.finished),
        _messiah.id: _entry(_messiah, ReadingStatus.dnf),
      };
      expect(
        BookSeries.nextToRead([_messiah, _dune, _children], shelf),
        _children,
      );
      expect(BookSeries.nextToRead([_dune], shelf), isNull);
    });

    test('names match ignoring case and spacing', () {
      const series = BookSeries(id: 's', name: 'The Expanse');
      expect(series.matches('  the   expanse '), isTrue);
      expect(series.matches('expanse'), isFalse);
    });

    test('groups a shelf by series, in series order', () {
      final groups = SeriesGroup.fromShelf([
        _entry(_messiah, ReadingStatus.reading),
        _entry(_book('9', 'Circe'), ReadingStatus.reading),
        _entry(_dune, ReadingStatus.finished),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Dune');
      expect(groups.single.entries.map((e) => e.book.title), [
        'Dune',
        'Dune Messiah',
      ]);
      expect(groups.single.summary, '2 books · 1 finished');
    });
  });

  group('Book series fields', () {
    test('parse from a row with the series embedded', () {
      final book = Book.fromRow({
        'id': 'b',
        'title': 'Dune Messiah',
        'series_id': 's1',
        'series_position': '2.0',
        'series': {'id': 's1', 'name': 'Dune'},
      });
      expect(book.seriesId, 's1');
      expect(book.seriesName, 'Dune');
      expect(book.seriesPosition, 2);
      expect(book.seriesLabel, 'Dune #2');
    });

    test('a novella number keeps its half', () {
      expect(
        _book('x', 'x', series: 'Dune', position: 1.5).seriesLabel,
        'Dune #1.5',
      );
      expect(_book('x', 'x').seriesLabel, isNull);
    });
  });

  group('LibrarySearch', () {
    final entry = _entry(_messiah, ReadingStatus.reading);

    test('every word must appear somewhere, in any order', () {
      expect(LibrarySearch.matches(entry, 'messiah herbert'), isTrue);
      expect(LibrarySearch.matches(entry, 'HERBERT'), isTrue);
      expect(LibrarySearch.matches(entry, 'messiah tolkien'), isFalse);
      expect(LibrarySearch.matches(entry, '   '), isTrue);
    });

    test('matches series and tags', () {
      expect(LibrarySearch.matches(entry, 'dune'), isTrue);
      expect(LibrarySearch.matches(entry, 'sci-fi'), isFalse);
      expect(LibrarySearch.matches(entry, 'sci-fi', tags: ['Sci-Fi']), isTrue);
    });

    test('ignores accents', () {
      final accented = _entry(
        _book('7', 'Les Misérables'),
        ReadingStatus.toBeRead,
      );
      expect(LibrarySearch.matches(accented, 'miserables'), isTrue);
    });
  });

  group('LibraryController series commands', () {
    test('series files a shelf book and updates it locally', () async {
      final series = _FakeSeries(catalogue: [_book('2', 'Dune Messiah')]);
      final (controller, _) = await _controller([
        _entry(_book('2', 'Dune Messiah'), ReadingStatus.toBeRead),
      ], series);

      final result = await controller.setSeries(
        'dune messiah',
        'Dune',
        position: 2,
      );

      expect(result.success, isTrue);
      expect(result.message, 'Filed "Dune Messiah" under Dune #2');
      expect(series.calls.single, ('2', 'Dune', 2.0));
      expect(controller.match('Dune Messiah')!.book.seriesLabel, 'Dune #2');
      expect(controller.seriesGroups.single.name, 'Dune');
    });

    test('series refuses a book that is not on the shelf', () async {
      final series = _FakeSeries();
      final (controller, _) = await _controller([], series);

      final result = await controller.setSeries('Dune', 'Dune');
      expect(result.success, isFalse);
      expect(series.calls, isEmpty);
    });

    test('series reports a locked series as a failure', () async {
      final series = _FakeSeries(
        failure: const InvalidInputException(
          'That book is already filed in a series by another reader.',
        ),
      );
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.reading),
      ], series);

      final result = await controller.setSeries('Dune', 'Wrong');
      expect(result.success, isFalse);
      expect(result.message, contains('already filed'));
    });

    test('start series adds the first unread book when none is on the '
        'shelf', () async {
      final series = _FakeSeries(catalogue: [_messiah, _dune]);
      final (controller, shelf) = await _controller([], series);

      final result = await controller.startSeries('dune');

      expect(result.success, isTrue);
      expect(result.message, 'Started "Dune" from Dune');
      expect(shelf.started, [_dune.id]);
      expect(controller.match('Dune')!.isReading, isTrue);
    });

    test('start series moves the next queued book to reading, skipping '
        'finished ones', () async {
      final series = _FakeSeries(catalogue: [_dune, _messiah, _children]);
      final (controller, shelf) = await _controller([
        _entry(_dune, ReadingStatus.finished),
        _entry(_messiah, ReadingStatus.toBeRead),
      ], series);

      final result = await controller.startSeries('Dune');

      expect(result.message, 'Started "Dune Messiah" from Dune');
      expect(shelf.moved, [ReadingStatus.reading]);
      expect(shelf.started, isEmpty);
    });

    test('start series refuses while a book in it is being read', () async {
      final series = _FakeSeries(catalogue: [_dune, _messiah]);
      final (controller, shelf) = await _controller([
        _entry(_messiah, ReadingStatus.reading),
      ], series);

      final result = await controller.startSeries('Dune');

      expect(result.success, isFalse);
      expect(result.message, contains('already reading "Dune Messiah"'));
      expect(shelf.started, isEmpty);
    });

    test('start series with nothing left, or no such series', () async {
      final series = _FakeSeries(catalogue: [_dune]);
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.finished),
      ], series);

      expect(
        (await controller.startSeries('Dune')).message,
        "You've read every book in Dune we know about.",
      );
      expect(
        (await controller.startSeries('Discworld')).message,
        contains('No series called "Discworld" yet'),
      );
    });
  });
}
