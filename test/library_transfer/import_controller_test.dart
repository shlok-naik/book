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
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library_transfer/data/library_transfer_repository.dart';
import 'package:book/features/library_transfer/domain/goodreads_import.dart';
import 'package:book/features/library_transfer/presentation/controllers/import_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_collections.dart';

const _csv =
    'Title,Author,ISBN13,My Rating,Exclusive Shelf,Date Read,Bookshelves\n'
    '"Dune (Dune, #1)",Frank Herbert,="9780441172719",5,read,2024/03/17,sci-fi\n'
    'Piranesi,Susanna Clarke,,0,to-read,,\n'
    'Nonexistent Book,Nobody,,0,read,,\n'
    'Dune,Frank Herbert,,4,read,,\n';

const _dune = Book(
  id: 'dune',
  googleBooksId: 'g-dune',
  title: 'Dune',
  author: 'Frank Herbert',
  pageCount: 604,
);
const _piranesi = Book(
  id: 'piranesi',
  googleBooksId: 'g-p',
  title: 'Piranesi',
  author: 'Susanna Clarke',
  pageCount: 272,
);

class _Lookup extends BookLookupService {
  _Lookup({this.networkFailures = 0})
    : super(
        cache: BookCacheRepository(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

  int networkFailures;
  final isbnCalls = <String>[];

  @override
  Future<Book> findOrFetchByIsbn(String isbn) async {
    isbnCalls.add(isbn);
    if (isbn == '9780441172719') return _dune;
    throw const BookNotFoundException('nope');
  }

  @override
  Future<Book> findOrFetch(String rawQuery, {String? author}) async {
    if (networkFailures > 0) {
      networkFailures--;
      throw const NetworkException('rate limited');
    }
    return switch (rawQuery.toLowerCase()) {
      'dune' => _dune,
      'piranesi' => _piranesi,
      _ => throw const BookNotFoundException('nope'),
    };
  }
}

class _Transfer extends LibraryTransferRepository {
  _Transfer({this.failure});

  final LibraryException? failure;
  List<ImportedBook>? replaced;

  @override
  Future<int> replaceLibrary(List<ImportedBook> books) async {
    if (failure != null) throw failure!;
    replaced = books;
    return books.length;
  }

  int marks = 0;

  @override
  Future<DateTime?> markImported() async {
    marks++;
    return DateTime.utc(2026, 9, 1);
  }
}

class _Series extends BookSeriesRepository {
  final filed = <(String, String, double?)>[];
  final made = <String>[];

  /// The import makes each series before filing into it — the same
  /// make-first path as `make series`.
  @override
  Future<BookSeries> makeSeries(String name) async {
    made.add(name);
    return BookSeries(id: 'series-$name', name: name);
  }

  @override
  Future<void> setSeries(
    String userBookId,
    String seriesId, {
    double? position,
  }) async {
    filed.add((userBookId, seriesId, position));
  }
}

/// Stands in for the shelf a real reload would return: once
/// `replaceLibrary` has recorded what was imported, `fetchLibrary` serves
/// it back as real rows, so `addToSeries` (which matches by title, like
/// the typed command) has something to find.
class _Shelf extends UserBookRepository {
  _Shelf(this.transfer);

  final _Transfer transfer;
  int loads = 0;

  static const _books = {'dune': _dune, 'piranesi': _piranesi};

  @override
  Future<List<LibraryBook>> fetchLibrary() async {
    loads++;
    final replaced = transfer.replaced;
    if (replaced == null) return const [];
    return [
      for (final imported in replaced)
        if (_books[imported.bookId] case final book?)
          LibraryBook(
            book: book,
            progress: UserBook(
              id: 'progress-${imported.bookId}',
              bookId: imported.bookId,
              currentPage: imported.currentPage,
              status: imported.status,
            ),
          ),
    ];
  }
}

class _Events extends ReadingEventRepository {
  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => const [];
}

void main() {
  late _Lookup lookup;
  late _Transfer transfer;
  late _Series series;
  late _Shelf shelf;
  late FakeCollectionsRepository collections;

  ImportController build({int networkFailures = 0, LibraryException? fail}) {
    lookup = _Lookup(networkFailures: networkFailures);
    transfer = _Transfer(failure: fail);
    series = _Series();
    shelf = _Shelf(transfer);
    collections = FakeCollectionsRepository();
    return ImportController(
      lookup: lookup,
      transfer: transfer,
      library: LibraryController(
        lookup: lookup,
        userBooks: shelf,
        events: _Events(),
        collections: collections,
        series: series,
      ),
      concurrency: 2,
      retryDelay: Duration.zero,
    );
  }

  test(
    'matches ISBN first, then title; reports misses and duplicates',
    () async {
      final controller = build();
      await controller.start(_csv);

      expect(controller.stage, ImportStage.review);
      expect(controller.total, 4);
      expect(controller.processed, 4);
      expect(lookup.isbnCalls, ['9780441172719']);
      expect(controller.matched.map((m) => m.$2.id), ['dune', 'piranesi']);
      expect(controller.unmatched.single.row.title, 'Nonexistent Book');
      expect(controller.duplicates, 1);
      expect(
        transfer.replaced,
        isNull,
        reason: 'nothing written before confirm',
      );
    },
  );

  test('confirm replaces the library, files series and reloads', () async {
    final controller = build();
    await controller.start(_csv);
    await controller.confirm();

    expect(controller.stage, ImportStage.done);
    expect(controller.imported, 2);
    final dune = transfer.replaced!.first;
    expect(dune.bookId, 'dune');
    expect(dune.status, ReadingStatus.finished);
    expect(dune.currentPage, 604);
    expect(dune.rating, 5);
    expect(dune.finishedAt, DateTime(2024, 3, 17, 12));
    expect(dune.tags, ['sci-fi']);
    expect(
      collections.tags.map((t) => t.name),
      ['sci-fi'],
      reason: "the file's tags are made before the replace links them",
    );
    expect(transfer.replaced![1].currentPage, 0);
    expect(series.made, ['Dune'], reason: 'made first, never implicitly');
    expect(series.filed, [('progress-dune', 'series-Dune', 1.0)]);
    expect(shelf.loads, greaterThan(0));
    expect(transfer.marks, 1, reason: 'the stats baseline is stamped');
  });

  test('a failed replace ends in failed and still reloads the shelf', () async {
    final controller = build(fail: const RemoteDataException('nope'));
    await controller.start(_csv);
    await controller.confirm();

    expect(controller.stage, ImportStage.failed);
    expect(controller.errorMessage, 'nope');
    expect(shelf.loads, greaterThan(0));
    expect(transfer.marks, 0, reason: 'nothing was imported to mark');
  });

  test('a network hiccup is retried once', () async {
    final controller = build(networkFailures: 1);
    await controller.start(_csv);
    expect(controller.matched, hasLength(2));
  });

  test('a file that is not an export fails without matching', () async {
    final controller = build();
    await controller.start('nonsense,columns\n1,2\n');
    expect(controller.stage, ImportStage.failed);
    expect(controller.errorMessage, contains('Title column'));
  });

  test('toImported clamps progress to the book and drops a date on an '
      'unfinished book', () {
    const row = ImportRow(
      line: 2,
      title: 'Piranesi',
      author: '',
      status: ReadingStatus.reading,
      currentPage: 900,
    );
    final imported = ImportController.toImported(row, _piranesi);
    expect(imported.currentPage, 272);
    expect(imported.finishedAt, isNull);
  });
}
