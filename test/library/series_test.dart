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

  /// The reader's own series list — what `add series` requires.
  final mine = <BookSeries>[];

  @override
  Future<List<BookSeries>> fetchMySeries() async => List.of(mine);

  @override
  Future<MadeSeries> makeSeries(String name) async {
    final made = BookSeries(id: 'series-${name.toLowerCase()}', name: name);
    mine.add(made);
    return MadeSeries(made, createdNew: true, alreadyYours: false);
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
    test('add series files a shelf book under a series made first and '
        'updates it locally', () async {
      final series = _FakeSeries(catalogue: [_book('2', 'Dune Messiah')]);
      final (controller, _) = await _controller([
        _entry(_book('2', 'Dune Messiah'), ReadingStatus.toBeRead),
      ], series);
      await controller.makeSeries('Dune');

      final result = await controller.addToSeries(
        'dune messiah',
        'dune',
        position: 2,
      );

      expect(result.success, isTrue);
      expect(result.message, 'Filed "Dune Messiah" under Dune #2');
      expect(
        series.calls.single,
        ('2', 'Dune', 2.0),
        reason: 'filed under the stored spelling of the made series',
      );
      expect(controller.match('Dune Messiah')!.book.seriesLabel, 'Dune #2');
      expect(controller.seriesGroups.single.name, 'Dune');
    });

    test('add series refuses a series that was never made', () async {
      final series = _FakeSeries();
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.reading),
      ], series);

      final result = await controller.addToSeries('Dune', 'Dune');

      expect(result.success, isFalse);
      expect(
        result.message,
        'No series called "Dune" yet — make it first with make series Dune.',
      );
      expect(series.calls, isEmpty);
      expect(series.mine, isEmpty, reason: 'never created implicitly');
    });

    test('add series refuses a book that is not on the shelf', () async {
      final series = _FakeSeries();
      final (controller, _) = await _controller([], series);
      await controller.makeSeries('Dune');

      final result = await controller.addToSeries('Dune', 'Dune');
      expect(result.success, isFalse);
      expect(series.calls, isEmpty);
    });

    test('add series reports a locked series as a failure', () async {
      final series = _FakeSeries(
        failure: const InvalidInputException(
          'That book is already filed in a series by another reader.',
        ),
      );
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.reading),
      ], series);
      await controller.makeSeries('Wrong');

      final result = await controller.addToSeries('Dune', 'Wrong');
      expect(result.success, isFalse);
      expect(result.message, contains('already filed'));
    });
  });
}
