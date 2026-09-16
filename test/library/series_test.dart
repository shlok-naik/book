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

Book _book(String id, String title) => Book(
  id: id,
  googleBooksId: 'g-$id',
  title: title,
  author: 'Frank Herbert',
  pageCount: 300,
);

LibraryBook _entry(
  Book book,
  ReadingStatus status, {
  String? seriesId,
  double? seriesPosition,
}) => LibraryBook(
  book: book,
  progress: UserBook(
    id: 'u-${book.id}',
    bookId: book.id,
    currentPage: 0,
    status: status,
    seriesId: seriesId,
    seriesPosition: seriesPosition,
  ),
);

final _dune = _book('1', 'Dune');
final _messiah = _book('2', 'Dune Messiah');
final _children = _book('3', 'Children of Dune');
final _novella = _book('4', 'Dune: A Novella');
const _duneSeries = BookSeries(id: 'series-dune', name: 'Dune');

class _FakeSeries extends BookSeriesRepository {
  _FakeSeries({this.failure});

  final LibraryException? failure;
  final calls = <(String, String, double?)>[];

  @override
  Future<void> setSeries(
    String userBookId,
    String seriesId, {
    double? position,
  }) async {
    if (failure != null) throw failure!;
    calls.add((userBookId, seriesId, position));
  }

  final cleared = <String>[];

  @override
  Future<void> clearSeries(String userBookId) async {
    if (failure != null) throw failure!;
    cleared.add(userBookId);
  }

  /// The reader's own series list — what `add series` requires.
  final mine = <BookSeries>[];

  @override
  Future<List<BookSeries>> fetchMySeries() async => List.of(mine);

  @override
  Future<BookSeries> makeSeries(String name) async {
    final made = BookSeries(id: 'series-${name.toLowerCase()}', name: name);
    mine.add(made);
    return made;
  }
}

class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;
  final started = <String>[];
  final moved = <ReadingStatus>[];

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<StartOutcome> start(String bookId, {DateTime? startedAt}) async {
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
      final entries = [
        _entry(_novella, ReadingStatus.reading, seriesId: 'series-dune'),
        _entry(
          _children,
          ReadingStatus.reading,
          seriesId: 'series-dune',
          seriesPosition: 3,
        ),
        _entry(
          _dune,
          ReadingStatus.reading,
          seriesId: 'series-dune',
          seriesPosition: 1,
        ),
        _entry(
          _messiah,
          ReadingStatus.reading,
          seriesId: 'series-dune',
          seriesPosition: 2,
        ),
      ];
      expect(BookSeries.sortEntries(entries).map((e) => e.book.title), [
        'Dune',
        'Dune Messiah',
        'Children of Dune',
        'Dune: A Novella',
      ]);
    });

    test('names match ignoring case and spacing', () {
      const series = BookSeries(id: 's', name: 'The Expanse');
      expect(series.matches('  the   expanse '), isTrue);
      expect(series.matches('expanse'), isFalse);
    });

    test('groups a shelf by series, in series order', () {
      final groups = SeriesGroup.fromShelf(
        [
          _entry(
            _messiah,
            ReadingStatus.reading,
            seriesId: 'series-dune',
            seriesPosition: 2,
          ),
          _entry(_book('9', 'Circe'), ReadingStatus.reading),
          _entry(
            _dune,
            ReadingStatus.finished,
            seriesId: 'series-dune',
            seriesPosition: 1,
          ),
        ],
        const [_duneSeries],
      );
      expect(groups, hasLength(1));
      expect(groups.single.name, 'Dune');
      expect(groups.single.entries.map((e) => e.book.title), [
        'Dune',
        'Dune Messiah',
      ]);
      expect(groups.single.summary, '2 books · 1 finished');
    });

    test('a book filed under a series the reader no longer has groups '
        'under nothing', () {
      final groups = SeriesGroup.fromShelf([
        _entry(_dune, ReadingStatus.reading, seriesId: 'series-gone'),
      ], const []);
      expect(groups, isEmpty);
    });
  });

  group('BookSeries.formatPosition', () {
    test('a novella number keeps its half', () {
      expect(BookSeries.formatPosition(1.5), '1.5');
      expect(BookSeries.formatPosition(2), '2');
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
      final unrelated = _entry(
        _book('9', 'Some Other Title'),
        ReadingStatus.reading,
      );
      expect(
        LibrarySearch.matches(unrelated, 'dune', seriesName: 'Dune'),
        isTrue,
      );
      expect(LibrarySearch.matches(unrelated, 'dune'), isFalse);
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
      final series = _FakeSeries();
      final (controller, _) = await _controller([
        _entry(_messiah, ReadingStatus.toBeRead),
      ], series);
      await controller.makeSeries('Dune', isPro: true);
      final made = controller.findSeries('Dune')!;

      final result = await controller.addToSeries(
        'dune messiah',
        'dune',
        position: 2,
      );

      expect(result.success, isTrue);
      expect(result.message, 'Filed "Dune Messiah" under Dune #2');
      expect(series.calls.single, (
        'u-2',
        made.id,
        2.0,
      ), reason: 'filed under this reader\'s own series');
      expect(controller.match('Dune Messiah')!.seriesId, made.id);
      expect(
        controller.seriesLabelFor(controller.match('Dune Messiah')!),
        'Dune #2',
      );
      expect(controller.seriesGroups.single.name, 'Dune');
    });

    test('add series refuses a series that was never made', () async {
      final series = _FakeSeries();
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.reading),
      ], series);

      final result = await controller.addToSeries('Dune', 'Dune');

      expect(result.success, isFalse);
      expect(result.message, 'No series "Dune". Try: make series Dune');
      expect(series.calls, isEmpty);
      expect(series.mine, isEmpty, reason: 'never created implicitly');
    });

    test('add series refuses a book that is not on the shelf', () async {
      final series = _FakeSeries();
      final (controller, _) = await _controller([], series);
      await controller.makeSeries('Dune', isPro: true);

      final result = await controller.addToSeries('Dune', 'Dune');
      expect(result.success, isFalse);
      expect(series.calls, isEmpty);
    });

    test('add series rolls back and reports a failed save', () async {
      final series = _FakeSeries(
        failure: const NetworkException("You're offline"),
      );
      final (controller, _) = await _controller([
        _entry(_dune, ReadingStatus.reading),
      ], series);
      await controller.makeSeries('Dune', isPro: true);

      final result = await controller.addToSeries('Dune', 'Dune');
      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(controller.match('Dune')!.seriesId, isNull);
    });
  });
}
