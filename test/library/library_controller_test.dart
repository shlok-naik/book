import 'dart:async';

import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_details_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/book_series_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_details_service.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/book_series.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_collections.dart';

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
  coverUrl: 'https://example.test/dune.jpg',
  pageCount: 400,
);

/// A book whose page count Google Books never reported — the degraded
/// case the UI has to keep working for.
const _untitledLength = Book(
  id: 'book-2',
  googleBooksId: 'gb-x',
  title: 'Pale Fire',
  author: 'Vladimir Nabokov',
);

/// In-memory `user_books` table.
class FakeUserBookRepository extends UserBookRepository {
  FakeUserBookRepository(this.rows);

  final List<LibraryBook> rows;
  LibraryException? failure;
  int saves = 0;
  int deletes = 0;
  final List<String> deletedIds = [];

  /// Tracks the shelf status already given to a book id, so a second
  /// [start]/[addWithStatus] call can report [StartOutcome.alreadyExists]
  /// *and* return the row's real (unchanged) status — mirrors what the
  /// real upsert-then-select does against Supabase's single
  /// `user_books` table, regardless of which method created the row.
  final Map<String, ReadingStatus> _statusByBookId = {};

  /// When set, [fetchLibrary] waits on it — lets a test hold a load in
  /// flight and act while it is.
  Completer<void>? fetchGate;
  int fetches = 0;
  int starts = 0;

  /// A non-[LibraryException] for [fetchLibrary] to throw — a parse bug.
  Error? fetchError;

  @override
  Future<List<LibraryBook>> fetchLibrary() async {
    fetches++;
    if (fetchError case final error?) throw error;
    // Captured before the wait: what the shelf held when this load started.
    final snapshot = List.of(rows);
    final gate = fetchGate;
    if (gate != null) await gate.future;
    if (failure != null) throw failure!;
    return snapshot;
  }

  @override
  Future<StartOutcome> start(String bookId, {DateTime? startedAt}) async {
    starts++;
    if (failure != null) throw failure!;
    final existing = _statusByBookId[bookId];
    _statusByBookId.putIfAbsent(bookId, () => ReadingStatus.reading);
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: existing ?? ReadingStatus.reading,
        startedAt: (startedAt ?? DateTime.now()).toUtc(),
      ),
      alreadyExists: existing != null,
    );
  }

  @override
  Future<StartOutcome> addWithStatus(
    String bookId,
    ReadingStatus status, {
    int currentPage = 0,
    String? shelfId,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    if (failure != null) throw failure!;
    final existing = _statusByBookId[bookId];
    _statusByBookId.putIfAbsent(bookId, () => status);
    final actual = existing ?? status;
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: existing == null ? currentPage : 0,
        status: actual,
        shelfId: existing == null ? shelfId : null,
        startedAt: (startedAt ?? DateTime.now()).toUtc(),
        finishedAt: actual == ReadingStatus.finished
            ? (finishedAt ?? DateTime.now()).toUtc()
            : null,
      ),
      alreadyExists: existing != null,
    );
  }

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
  }) async {
    saves++;
    if (failure != null) throw failure!;
    final existing = rows
        .where((e) => e.progress.id == userBookId)
        .firstOrNull
        ?.progress;
    return UserBook(
      id: userBookId,
      bookId: 'book',
      // The real row comes back with its custom shelf, and its
      // reread count, untouched — neither is a column this update sends.
      shelfId: existing?.shelfId,
      currentPage: currentPage,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
      finishedAt: finished ? (finishedAt ?? DateTime.now()).toUtc() : null,
      rereadCount:
          _rereadCountByUserBookId[userBookId] ?? existing?.rereadCount ?? 0,
    );
  }

  final Map<String, int> _rereadCountByUserBookId = {};

  @override
  Future<void> delete(String userBookId) async {
    deletes++;
    if (failure != null) throw failure!;
    deletedIds.add(userBookId);
  }

  final List<UserBook> shelfChanges = [];
  final List<List<String>> savedOrders = [];
  final List<(String, String?, int)> ownedEditions = [];

  /// Set to fail only [saveShelfOrder], after a [changeShelf] succeeded —
  /// the half-way failure where the move landed but its spot didn't.
  LibraryException? orderFailure;

  /// What `fetchImportedAt` answers — the stats baseline.
  DateTime? importedAt;

  @override
  Future<DateTime?> fetchImportedAt() async => importedAt;

  final savedDates = <(String, DateTime, DateTime?)>[];

  @override
  Future<UserBook> saveDates(
    String userBookId, {
    required DateTime startedAt,
    DateTime? finishedAt,
  }) async {
    if (failure != null) throw failure!;
    savedDates.add((userBookId, startedAt, finishedAt));
    final existing = rows
        .where((e) => e.progress.id == userBookId)
        .firstOrNull
        ?.progress;
    return UserBook(
      id: userBookId,
      bookId: existing?.bookId ?? 'book',
      currentPage: existing?.currentPage ?? 0,
      status: existing?.status ?? ReadingStatus.reading,
      startedAt: startedAt.toUtc(),
      finishedAt: finishedAt?.toUtc(),
    );
  }

  @override
  Future<UserBook> changeShelf(UserBook updated) async {
    if (failure != null) throw failure!;
    shelfChanges.add(updated);
    _statusByBookId[updated.bookId] = updated.status;
    // Mirrors the server: the row comes back as written, with the
    // position cleared by the status-change trigger.
    return updated.copyWith(clearShelfPosition: true);
  }

  @override
  Future<void> saveShelfOrder(List<String> orderedIds) async {
    if (failure != null) throw failure!;
    if (orderFailure != null) throw orderFailure!;
    savedOrders.add(orderedIds);
  }

  @override
  Future<UserBook> setOwnedEdition(
    String userBookId,
    String? editionId, {
    required int currentPage,
  }) async {
    if (failure != null) throw failure!;
    ownedEditions.add((userBookId, editionId, currentPage));
    final existing = rows.firstWhere((e) => e.progress.id == userBookId);
    return editionId == null
        ? existing.progress.copyWith(
            clearOwnedEdition: true,
            currentPage: currentPage,
          )
        : existing.progress.copyWith(
            ownedEditionId: editionId,
            currentPage: currentPage,
          );
  }

  int rates = 0;

  @override
  Future<UserBook> rate({
    required String userBookId,
    required double rating,
  }) async {
    rates++;
    if (failure != null) throw failure!;
    return UserBook(
      id: userBookId,
      bookId: 'book',
      currentPage: 400,
      status: ReadingStatus.finished,
      rating: rating,
    );
  }

  final List<(String userBookId, int rereadCount)> restarts = [];

  @override
  Future<UserBook> restart({
    required String userBookId,
    required int rereadCount,
  }) async {
    restarts.add((userBookId, rereadCount));
    if (failure != null) throw failure!;
    _rereadCountByUserBookId[userBookId] = rereadCount;
    return UserBook(
      id: userBookId,
      bookId: 'book',
      currentPage: 0,
      status: ReadingStatus.reading,
      rereadCount: rereadCount,
    );
  }
}

/// In-memory `reading_events` log — records what [LibraryController] logs
/// instead of reaching the real Supabase client, so controller tests
/// never depend on network behaviour for the streaks-logging side effect
/// either.
class FakeReadingEventRepository extends ReadingEventRepository {
  final List<
    ({ReadingEventType type, String title, DateTime? occurredAt, double? value})
  >
  logged = [];

  /// What most tests actually care about — `LibraryController._logEvent`
  /// always resolves `occurredAt` to a concrete timestamp (the given
  /// date, or "now") before it ever reaches here, so it's never
  /// actually null and never test-repeatable; only the backdating tests
  /// need the real value, via [logged] itself.
  List<({ReadingEventType type, String title})> get loggedTypesAndTitles => [
    for (final entry in logged) (type: entry.type, title: entry.title),
  ];

  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {
    logged.add((
      type: type,
      title: title,
      occurredAt: occurredAt,
      value: value,
    ));
  }

  /// What `deleteBook` calls instead of logging one more event — see
  /// `LibraryController._clearJournal`.
  final List<String> clearedTitles = [];

  @override
  Future<void> deleteForTitle(String title) async {
    clearedTitles.add(title);
  }
}

/// In-memory `book_tags`/`book_comments` for the `add tag`/`add comment`
/// commands.
class FakeBookNotesRepository extends BookNotesRepository {
  final List<(String userBookId, String tag)> tags = [];
  final List<(String userBookId, String body)> comments = [];
  LibraryException? failure;

  /// Every comment `fetchComments` knows, per book — seed it directly.
  final storedComments = <BookComment>[];
  final deletedComments = <String>[];
  final removedTags = <String>[];

  @override
  Future<List<BookTag>> fetchTags(String userBookId) async {
    if (failure != null) throw failure!;
    return [
      for (final (i, (bookId, tag)) in tags.indexed)
        if (bookId == userBookId)
          BookTag(
            id: 'book-tag-${i + 1}',
            userBookId: bookId,
            tag: tag,
            createdAt: DateTime(2026),
          ),
    ];
  }

  @override
  Future<void> removeTag(String tagId) async {
    if (failure != null) throw failure!;
    removedTags.add(tagId);
  }

  @override
  Future<List<BookComment>> fetchComments(String userBookId) async {
    if (failure != null) throw failure!;
    return [
      for (final comment in storedComments)
        if (comment.userBookId == userBookId) comment,
    ];
  }

  @override
  Future<void> deleteComment(String commentId) async {
    if (failure != null) throw failure!;
    deletedComments.add(commentId);
    storedComments.removeWhere((c) => c.id == commentId);
  }

  @override
  Future<BookTag> addTag(String userBookId, ReaderTag tag) async {
    if (failure != null) throw failure!;
    tags.add((userBookId, tag.name));
    return BookTag(
      id: 'book-tag-${tags.length}',
      userBookId: userBookId,
      tag: tag.name,
      createdAt: DateTime(2026),
    );
  }

  @override
  Future<BookComment> addComment(String userBookId, String body) async {
    final clean = BookNotesRepository.validateComment(body);
    if (failure != null) throw failure!;
    comments.add((userBookId, clean));
    return BookComment(
      id: 'comment-${comments.length}',
      userBookId: userBookId,
      body: clean,
      createdAt: DateTime(2026),
    );
  }
}

/// In-memory series list — `make series` and `add series` without Supabase.
/// Private to the reader, like [FakeCollectionsRepository]'s shelves/tags.
class FakeSeriesRepository extends BookSeriesRepository {
  final List<BookSeries> mine = [];
  final List<(String userBookId, String seriesId, double? position)> filed = [];

  @override
  Future<List<BookSeries>> fetchMySeries() async => List.of(mine);

  @override
  Future<BookSeries> makeSeries(String name) async {
    final clean = CollectionNames.validateSeries(name);
    for (final series in mine) {
      if (series.matches(clean)) {
        throw InvalidInputException('Series "$clean" exists.');
      }
    }
    final made = BookSeries(id: 'series-${mine.length + 1}', name: clean);
    mine.add(made);
    return made;
  }

  @override
  Future<void> setSeries(
    String userBookId,
    String seriesId, {
    double? position,
  }) async {
    filed.add((userBookId, seriesId, position));
  }

  final cleared = <String>[];
  final deleted = <String>[];

  @override
  Future<void> clearSeries(String userBookId) async => cleared.add(userBookId);

  @override
  Future<void> deleteSeries(String id) async {
    deleted.add(id);
    mine.removeWhere((s) => s.id == id);
  }
}

/// Records every book `LibraryController._warmEditions` asks it to cache,
/// without touching the network or Supabase.
class SpyBookDetailsService extends BookDetailsService {
  SpyBookDetailsService()
    : super(
        cache: BookDetailsRepository(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('unused', 500)),
        ),
      );

  final warmed = <String>[];
  LibraryException? failure;

  @override
  Future<List<BookEdition>> editionsFor(Book book) async {
    warmed.add(book.title);
    if (failure != null) throw failure!;
    return const [];
  }
}

/// Cache that always hits, so controller tests never depend on network
/// behaviour (that is covered in book_lookup_service_test.dart).
class AlwaysHitCache extends BookCacheRepository {
  AlwaysHitCache(this.book);

  final Book book;

  @override
  Future<Book?> findByTitle(String title, {String? author}) async => book;

  @override
  Future<Book?> findByGoogleBooksId(String id) async => book;

  @override
  Future<Book?> findByIsbn(String isbn) async => book;

  @override
  Future<Book> cache(GoogleBook volume) async => book;
}

LibraryBook _entry(
  Book book, {
  int page = 0,
  bool finished = false,
  ReadingStatus? status,
  double? position,
  double? rating,
  String? shelfId,
  int rereadCount = 0,
}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
      shelfId: shelfId,
      id: 'progress-${book.id}',
      bookId: book.id,
      currentPage: page,
      status:
          status ?? (finished ? ReadingStatus.finished : ReadingStatus.reading),
      shelfPosition: position,
      rating: rating,
      rereadCount: rereadCount,
    ),
  );
}

const _circe = Book(
  id: 'book-3',
  googleBooksId: 'gb-circe',
  title: 'Circe',
  author: 'Madeline Miller',
  pageCount: 300,
);

const _duneMessiah = Book(
  id: 'book-4',
  googleBooksId: 'gb-messiah',
  title: 'Dune Messiah',
  author: 'Frank Herbert',
  pageCount: 250,
);

void main() {
  late FakeUserBookRepository userBooks;
  late FakeReadingEventRepository events;
  late FakeBookNotesRepository notes;
  late FakeCollectionsRepository collections;
  late FakeSeriesRepository series;

  LibraryController controllerWith(
    List<LibraryBook> rows, {
    Book? cached,
    BookDetailsService? details,
    List<Shelf> shelves = const [],
  }) {
    userBooks = FakeUserBookRepository(rows);
    events = FakeReadingEventRepository();
    notes = FakeBookNotesRepository();
    collections = FakeCollectionsRepository(shelves: shelves);
    series = FakeSeriesRepository();
    return LibraryController(
      lookup: BookLookupService(
        cache: AlwaysHitCache(cached ?? _dune),
        googleBooks: GoogleBooksApiClient(
          client: MockClient(
            (_) async => http.Response('unused — cache always hits', 200),
          ),
        ),
      ),
      userBooks: userBooks,
      events: events,
      notes: notes,
      details: details,
      collections: collections,
      series: series,
    );
  }

  group('load', () {
    test('splits the shelf into in-progress and finished', () async {
      final controller = controllerWith([
        _entry(_dune, page: 120),
        _entry(_untitledLength, finished: true),
      ]);

      await controller.load();

      expect(controller.inProgress.map((e) => e.book.title), ['Dune']);
      expect(controller.finished.map((e) => e.book.title), ['Pale Fire']);
      expect(controller.errorMessage, isNull);
    });

    test(
      'surfaces a failure as a retryable message, not an exception',
      () async {
        final controller = controllerWith([])
          ..userBooksFailure = const NetworkException("You're offline");

        await controller.load();

        expect(controller.errorMessage, "You're offline");
        expect(controller.isLoading, isFalse);
      },
    );
  });

  group('startBook', () {
    test('puts a resolved book on the shelf and notifies', () async {
      final controller = controllerWith([]);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final result = await controller.startBook('Dune');

      expect(result.success, isTrue);
      expect(result.message, 'Started "Dune"');
      expect(controller.inProgress.single.book.title, 'Dune');
      expect(controller.inProgress.single.currentPage, 0);
      expect(notifications, greaterThan(0));
    });

    test('warms the shared edition cache for the newly started book', () async {
      final spy = SpyBookDetailsService();
      final controller = controllerWith([], details: spy);

      await controller.startBook('Dune');
      // The warm is fire-and-forget: give its Future a turn to run.
      await Future<void>.delayed(Duration.zero);

      expect(spy.warmed, ['Dune']);
    });

    test(
      'a failed edition warm is swallowed — it never fails the command',
      () async {
        final spy = SpyBookDetailsService()
          ..failure = const RemoteDataException('offline');
        final controller = controllerWith([], details: spy);

        final result = await controller.startBook('Dune');
        await Future<void>.delayed(Duration.zero);

        expect(result.success, isTrue);
        expect(spy.warmed, ['Dune']);
      },
    );

    test('logs a start event and broadcasts it on loggedEvents', () async {
      final controller = controllerWith([]);
      final broadcast = <ReadingEvent>[];
      controller.loggedEvents.listen(broadcast.add);

      await controller.startBook('Dune');
      await Future<void>.delayed(Duration.zero);

      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.start, title: 'Dune'),
      ]);
      expect(broadcast.single.type, ReadingEventType.start);
      expect(broadcast.single.title, 'Dune');
    });

    test('starting the same book twice fails the second time', () async {
      final controller = controllerWith([]);

      final first = await controller.startBook('Dune');
      final second = await controller.startBook('dune');

      expect(first.success, isTrue);
      expect(second.success, isFalse);
      expect(second.message, '"Dune" is already shelved.');
      // Still exactly one shelf entry — the repeat didn't duplicate it,
      // and didn't reset progress either.
      expect(controller.inProgress, hasLength(1));

      await Future<void>.delayed(Duration.zero);
      expect(
        events.loggedTypesAndTitles,
        [(type: ReadingEventType.start, title: 'Dune')],
        reason: 'the rejected repeat must not log a second start',
      );
    });

    test('backdates the reading event when given a date, not the shelf '
        'write itself', () async {
      final controller = controllerWith([]);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      final result = await controller.startBook('Dune', loggedAt: yesterday);
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(events.logged.single.occurredAt, yesterday.toUtc());
    });

    test(
      'refuses a future date without logging or touching the shelf',
      () async {
        final controller = controllerWith([]);
        final tomorrow = DateTime.now().add(const Duration(days: 1));

        final result = await controller.startBook('Dune', loggedAt: tomorrow);

        expect(result.success, isFalse);
        expect(result.message, 'Date is in the future.');
        expect(controller.inProgress, isEmpty);
        expect(events.logged, isEmpty);
      },
    );
  });

  group('startBookByIsbn', () {
    test('resolves the ISBN and puts the book on the shelf', () async {
      final controller = controllerWith([]);

      final result = await controller.startBookByIsbn('9780441172719');

      expect(result.success, isTrue);
      expect(result.message, 'Started "Dune"');
      expect(controller.inProgress.single.book.title, 'Dune');
    });

    test('scanning a book already on the shelf fails the same way '
        'starting it by title does', () async {
      final controller = controllerWith([]);

      final first = await controller.startBookByIsbn('9780441172719');
      final second = await controller.startBookByIsbn('9780441172719');

      expect(first.success, isTrue);
      expect(second.success, isFalse);
      expect(second.message, '"Dune" is already shelved.');
      expect(controller.inProgress, hasLength(1));
    });

    test(
      'refuses a future date without logging or touching the shelf',
      () async {
        final controller = controllerWith([]);
        final tomorrow = DateTime.now().add(const Duration(days: 1));

        final result = await controller.startBookByIsbn(
          '9780441172719',
          loggedAt: tomorrow,
        );

        expect(result.success, isFalse);
        expect(controller.inProgress, isEmpty);
        expect(events.logged, isEmpty);
      },
    );
  });

  group('moveToShelf', () {
    test('warms the shared edition cache for the newly shelved book', () async {
      final spy = SpyBookDetailsService();
      final controller = controllerWith([], details: spy);

      await controller.moveToShelf('Dune', 'tbr');
      await Future<void>.delayed(Duration.zero);

      expect(spy.warmed, ['Dune']);
    });

    test('move tbr puts a resolved book on the to-be-read shelf', () async {
      final controller = controllerWith([]);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final result = await controller.moveToShelf('Dune', 'tbr');

      expect(result.success, isTrue);
      expect(result.message, 'Added "Dune" to read');
      expect(controller.toBeRead.single.book.title, 'Dune');
      expect(controller.toBeRead.single.currentPage, 0);
      expect(controller.inProgress, isEmpty);
      expect(controller.finished, isEmpty);
      expect(notifications, greaterThan(0));
    });

    test(
      'move finished puts a new book on the finished shelf at 100%',
      () async {
        final controller = controllerWith([]);

        final result = await controller.moveToShelf('Dune', 'finished');

        expect(result.success, isTrue);
        expect(result.message, 'Added "Dune" as finished');
        final entry = controller.finished.single;
        expect(entry.book.title, 'Dune');
        expect(entry.currentPage, 400, reason: 'the last page — 100%');
        expect(entry.completion, 1);
      },
    );

    test('move reading adds a new book at page 0', () async {
      final controller = controllerWith([]);

      final result = await controller.moveToShelf('Dune', 'reading');

      expect(result.success, isTrue);
      expect(result.message, 'Started "Dune"');
      expect(controller.inProgress.single.currentPage, 0);
    });

    test('logs each shelf as its own journal event', () async {
      for (final (shelf, type) in [
        ('tbr', ReadingEventType.addToBeRead),
        ('finished', ReadingEventType.finish),
        ('dnf', ReadingEventType.dnf),
        ('reading', ReadingEventType.start),
      ]) {
        final controller = controllerWith([]);

        await controller.moveToShelf('Dune', shelf);
        await Future<void>.delayed(Duration.zero);

        expect(events.loggedTypesAndTitles, [(type: type, title: 'Dune')]);
      }
    });

    test('adding a book to the shelf it is already on fails', () async {
      final controller = controllerWith([]);

      await controller.moveToShelf('Dune', 'tbr');
      final second = await controller.moveToShelf('dune', 'tbr');

      expect(second.success, isFalse);
      expect(second.message, '"Dune" is already on your to-read shelf.');
      expect(controller.toBeRead, hasLength(1));
    });

    test('refuses a book already marked DNF', () async {
      final controller = controllerWith([]);
      await controller.moveToShelf('Dune', 'dnf');

      final result = await controller.moveToShelf('Dune', 'dnf');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already marked as DNF.');
    });
  });

  group('shelf changes and their side effects', () {
    test('moving a reading book to finished sets it to 100%', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'finished');

      expect(result.success, isTrue);
      expect(result.message, 'Finished "Dune"');
      final entry = controller.finished.single;
      expect(entry.currentPage, 400);
      expect(entry.completion, 1);
      expect(entry.progress.finishedAt, isNotNull);
      expect(userBooks.shelfChanges.single.currentPage, 400);
    });

    test('moving a book to finished without a page count keeps its page but '
        'still reads as complete', () async {
      final controller = controllerWith([
        _entry(_untitledLength, page: 80),
      ], cached: _untitledLength);
      await controller.load();

      await controller.moveToShelf('Pale Fire', 'finished');

      final entry = controller.finished.single;
      expect(entry.currentPage, 80);
      expect(entry.completion, 1);
    });

    test('moving a book to to read resets it to page 0', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      await controller.moveToShelf('Dune', 'tbr');

      expect(controller.toBeRead.single.currentPage, 0);
      expect(controller.toBeRead.single.completion, 0);
      expect(userBooks.shelfChanges.single.currentPage, 0);
    });

    test(
      'moving a finished book back to reading resets it to page 0 and clears '
      'its finish date',
      () async {
        final controller = controllerWith([
          _entry(_dune, page: 400, finished: true),
        ]);
        await controller.load();

        await controller.moveToShelf('Dune', 'reading');

        final entry = controller.inProgress.single;
        expect(entry.currentPage, 0);
        expect(entry.progress.finishedAt, isNull);
      },
    );

    test('moving a book to DNF keeps the page it reached', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'dnf');

      expect(result.success, isTrue);
      expect(result.message, 'Marked "Dune" as DNF');
      expect(controller.didNotFinish.single.currentPage, 120);
    });

    test('rolls a shelf change back when the write fails', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.moveToShelf('Dune', 'dnf');

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(controller.inProgress.single.currentPage, 120);
      expect(controller.didNotFinish, isEmpty);
    });

    test('finish applies the same 100% rule as a shelf move', () async {
      final controller = controllerWith([
        _entry(_dune, page: 12, status: ReadingStatus.toBeRead),
      ]);
      await controller.load();

      await controller.finishBook('Dune');

      expect(controller.finished.single.currentPage, 400);
    });
  });

  group('moveBook (drag and drop)', () {
    test(
      'reorders within a section without touching progress or the journal',
      () async {
        final controller = controllerWith([
          _entry(_dune, page: 10),
          _entry(_circe, page: 20),
          _entry(_duneMessiah, page: 30),
        ]);
        await controller.load();
        expect(controller.inProgress.map((e) => e.book.title), [
          'Dune',
          'Circe',
          'Dune Messiah',
        ]);

        final result = await controller.moveBook(
          'progress-book-4',
          const StatusShelfRef(ReadingStatus.reading),
          0,
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.success, isTrue);
        expect(result.message, isNull);
        expect(controller.inProgress.map((e) => e.book.title), [
          'Dune Messiah',
          'Dune',
          'Circe',
        ]);
        expect(controller.inProgress.first.currentPage, 30);
        expect(userBooks.shelfChanges, isEmpty);
        expect(userBooks.savedOrders.single, [
          'progress-book-4',
          'progress-book-1',
          'progress-book-3',
        ]);
        expect(events.logged, isEmpty);
      },
    );

    test(
      'moving down within a section accounts for its own old slot',
      () async {
        final controller = controllerWith([
          _entry(_dune),
          _entry(_circe),
          _entry(_duneMessiah),
        ]);
        await controller.load();

        // Dropped "before index 2" (before Dune Messiah) — lands second.
        await controller.moveBook(
          'progress-book-1',
          const StatusShelfRef(ReadingStatus.reading),
          2,
        );

        expect(controller.inProgress.map((e) => e.book.title), [
          'Circe',
          'Dune',
          'Dune Messiah',
        ]);
      },
    );

    test('dropping a book back where it was is a silent no-op', () async {
      final controller = controllerWith([_entry(_dune), _entry(_circe)]);
      await controller.load();

      final result = await controller.moveBook(
        'progress-book-1',
        const StatusShelfRef(ReadingStatus.reading),
        0,
      );

      expect(result.success, isFalse);
      expect(result.message, isNull);
      expect(userBooks.savedOrders, isEmpty);
    });

    test('moving into another section applies the shelf side effects and lands '
        'at the drop index', () async {
      final controller = controllerWith([
        _entry(_dune, page: 120),
        _entry(_circe, page: 300, finished: true, position: 0),
        _entry(_duneMessiah, page: 250, finished: true, position: 1),
      ]);
      await controller.load();

      final result = await controller.moveBook(
        'progress-book-1',
        const StatusShelfRef(ReadingStatus.finished),
        1,
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(result.message, 'Finished "Dune"');
      expect(controller.inProgress, isEmpty);
      expect(controller.finished.map((e) => e.book.title), [
        'Circe',
        'Dune',
        'Dune Messiah',
      ]);
      expect(controller.finished[1].currentPage, 400);
      expect(userBooks.shelfChanges.single.status, ReadingStatus.finished);
      expect(userBooks.savedOrders.single, [
        'progress-book-3',
        'progress-book-1',
        'progress-book-4',
      ]);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.finish, title: 'Dune'),
      ]);
    });

    test('dragging into to read resets progress to 0', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      await controller.moveBook(
        'progress-book-1',
        const StatusShelfRef(ReadingStatus.toBeRead),
        0,
      );

      expect(controller.toBeRead.single.currentPage, 0);
    });

    test(
      'rolls the whole shelf back if the shelf change itself fails',
      () async {
        final controller = controllerWith([
          _entry(_dune, page: 120),
          _entry(_circe, finished: true, page: 300),
        ]);
        await controller.load();
        userBooks.failure = const NetworkException("You're offline");

        final result = await controller.moveBook(
          'progress-book-1',
          const StatusShelfRef(ReadingStatus.finished),
          0,
        );

        expect(result.success, isFalse);
        expect(result.message, "You're offline");
        expect(controller.inProgress.single.currentPage, 120);
        expect(controller.finished.single.book.title, 'Circe');
      },
    );

    // Regression: this used to roll the book back onto "reading" even though
    // the server already had it finished — the screen and the database
    // disagreed until the next reload.
    test('keeps a shelf change that landed when only saving the order fails, '
        'and says the spot did not save', () async {
      final controller = controllerWith([
        _entry(_dune, page: 120),
        _entry(_circe, finished: true, page: 300, position: 0),
      ]);
      await controller.load();
      userBooks.orderFailure = const NetworkException("You're offline");

      final result = await controller.moveBook(
        'progress-book-1',
        const StatusShelfRef(ReadingStatus.finished),
        1,
      );

      expect(result.success, isFalse);
      expect(result.message, 'Finished "Dune", but its spot didn\'t save.');
      expect(controller.inProgress, isEmpty);
      final dune = controller.finished.firstWhere(
        (e) => e.book.title == 'Dune',
      );
      // Unplaced, as the server left it after the status change.
      expect(dune.progress.shelfPosition, isNull);
      // The other book's position is the one it had before the drop.
      final circe = controller.finished.firstWhere(
        (e) => e.book.title == 'Circe',
      );
      expect(circe.progress.shelfPosition, 0);
    });

    test('unplaced books sort ahead of placed ones', () async {
      final controller = controllerWith([
        _entry(_dune, position: 1),
        _entry(_circe),
        _entry(_duneMessiah, position: 0),
      ]);
      await controller.load();

      expect(controller.inProgress.map((e) => e.book.title), [
        'Circe',
        'Dune Messiah',
        'Dune',
      ]);
    });

    test('currentlyReading ignores manual order', () async {
      final controller = controllerWith([
        _entry(_dune, position: 1),
        _entry(_circe, position: 0),
      ]);
      await controller.load();

      expect(controller.inProgress.first.book.title, 'Circe');
      expect(
        controller.currentlyReading?.book.title,
        'Dune',
        reason: 'the most recently updated reading book, not the top tile',
      );
    });
  });

  group('making collections', () {
    test('make shelf adds a custom shelf the page can show at once', () async {
      final controller = controllerWith([]);
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final result = await controller.makeShelf(
        '  Summer   reads ',
        isPro: true,
      );

      expect(result.success, isTrue);
      expect(result.message, 'Made shelf "Summer reads"');
      expect(controller.shelves.single.name, 'Summer reads');
      expect(collections.shelves, hasLength(1));
      expect(notifications, greaterThan(0));
    });

    test(
      'make shelf refuses a duplicate, ignoring case, without a write',
      () async {
        final controller = controllerWith([]);
        await controller.load();
        await controller.makeShelf('Summer reads', isPro: true);

        final again = await controller.makeShelf('summer READS', isPro: true);

        expect(again.success, isFalse);
        expect(again.message, 'Shelf "summer READS" exists.');
        expect(collections.creates, 1);
      },
    );

    test('make shelf refuses a built-in shelf name', () async {
      final controller = controllerWith([]);

      for (final name in ['tbr', 'Reading', 'did not finish']) {
        final result = await controller.makeShelf(name, isPro: true);
        expect(result.success, isFalse, reason: name);
        expect(result.message, contains('built-in'));
      }
      expect(collections.creates, 0);
    });

    test('make shelf refuses an empty or overlong name', () async {
      final controller = controllerWith([]);

      expect(
        (await controller.makeShelf('   ', isPro: true)).message,
        'Name the shelf first.',
      );
      expect(
        (await controller.makeShelf('x' * 41, isPro: true)).message,
        'Max 40 characters.',
      );
    });

    test('make shelf surfaces a repository failure', () async {
      final controller = controllerWith([]);
      collections.failure = const NetworkException("You're offline");

      final result = await controller.makeShelf('Summer', isPro: true);

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(controller.shelves, isEmpty);
    });

    test(
      'make tag creates a standalone tag without touching any book',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        await controller.load();

        final result = await controller.makeTag('sci-fi', isPro: true);

        expect(result.success, isTrue);
        expect(result.message, 'Made tag "sci-fi"');
        expect(controller.tags.single.name, 'sci-fi');
        expect(
          notes.tags,
          isEmpty,
          reason: 'making a tag applies it to nothing',
        );
        expect(
          (await controller.makeTag('Sci-Fi', isPro: true)).success,
          isFalse,
        );
      },
    );

    test('make series makes a new series and refuses one already on the '
        'list', () async {
      final controller = controllerWith([]);

      final made = await controller.makeSeries('dune', isPro: true);
      final again = await controller.makeSeries('DUNE', isPro: true);

      expect(made.success, isTrue);
      expect(made.message, 'Made series "dune"');
      expect(again.success, isFalse);
      expect(again.message, 'Series "dune" exists.');
      expect(controller.mySeries.map((s) => s.name), ['dune']);
    });
  });

  group('collection caps', () {
    test('free plan allows no custom shelves at all', () async {
      final controller = controllerWith([]);
      await controller.load();

      expect(controller.canMakeShelf(false), isFalse);
      expect(controller.canMakeShelf(true), isTrue);

      final result = await controller.makeShelf('Summer', isPro: false);

      expect(result.success, isFalse);
      expect(result.message, contains('cactus pro'));
      expect(controller.shelves, isEmpty);
      expect(collections.creates, 0);
    });

    test('free plan allows up to 2 tags, pro is unlimited', () async {
      final controller = controllerWith([]);
      await controller.load();

      await controller.makeTag('one', isPro: false);
      expect(controller.canMakeTag(false), isTrue);
      await controller.makeTag('two', isPro: false);
      expect(controller.canMakeTag(false), isFalse);

      final blocked = await controller.makeTag('three', isPro: false);
      expect(blocked.success, isFalse);
      expect(blocked.message, contains('cactus pro'));
      expect(controller.tags, hasLength(2));

      final allowed = await controller.makeTag('three', isPro: true);
      expect(allowed.success, isTrue);
      expect(controller.tags, hasLength(3));
    });

    test('free plan allows up to 1 series, pro is unlimited', () async {
      final controller = controllerWith([]);
      await controller.load();

      await controller.makeSeries('dune', isPro: false);
      expect(controller.canMakeSeries(false), isFalse);

      final blocked = await controller.makeSeries('foundation', isPro: false);
      expect(blocked.success, isFalse);
      expect(blocked.message, contains('cactus pro'));
      expect(controller.mySeries, hasLength(1));

      final allowed = await controller.makeSeries('foundation', isPro: true);
      expect(allowed.success, isTrue);
      expect(controller.mySeries, hasLength(2));
    });
  });

  group('applying collections never creates them', () {
    test('add tag refuses a tag that was never made', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addTag('Dune', 'sci-fi');

      expect(result.success, isFalse);
      expect(result.message, 'No tag "sci-fi". Try: make tag sci-fi');
      expect(notes.tags, isEmpty);
      expect(controller.tags, isEmpty);
    });

    test('add series refuses a series that was never made', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addToSeries('Dune', 'dune', position: 1);

      expect(result.success, isFalse);
      expect(result.message, contains('make series dune'));
      expect(series.filed, isEmpty);
      expect(series.mine, isEmpty);
    });

    test('add series files the book under a series made first', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
      await controller.makeSeries('Dune', isPro: true);
      final made = controller.findSeries('Dune')!;

      final result = await controller.addToSeries('dune', 'dune', position: 1);

      expect(result.success, isTrue);
      expect(series.filed.single, ('progress-book-1', made.id, 1.0));
    });

    test('move refuses a shelf that was never made', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'summer reads');

      expect(result.success, isFalse);
      expect(
        result.message,
        'No shelf "summer reads". Try: make shelf summer reads',
      );
      expect(collections.shelves, isEmpty);
      expect(userBooks.shelfChanges, isEmpty);
    });
  });

  group('custom shelves', () {
    const summer = Shelf(id: 'shelf-summer', name: 'Summer reads');
    const summerRef = CustomShelfRef('shelf-summer');

    test('a book on a custom shelf is shown there, not in its status section, '
        'and still counts as what it is', () async {
      final controller = controllerWith(
        [
          _entry(_dune, page: 120, shelfId: summer.id),
          _entry(_circe, page: 20),
        ],
        shelves: [summer],
      );
      await controller.load();

      expect(controller.shelfSection(summerRef).single.book.title, 'Dune');
      expect(controller.inProgress.map((e) => e.book.title), ['Circe']);
      expect(controller.books.where((e) => e.isReading), hasLength(2));
    });

    test('a shelf id whose shelf failed to load falls back to its status '
        'section rather than vanishing', () async {
      final controller = controllerWith([
        _entry(_dune, page: 120, shelfId: 'shelf-gone'),
      ]);
      await controller.load();

      expect(controller.inProgress.single.book.title, 'Dune');
    });

    test('move to a custom shelf keeps progress and logs nothing', () async {
      final controller = controllerWith(
        [_entry(_dune, page: 120)],
        shelves: [summer],
      );
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'summer READS');
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(result.message, 'Moved "Dune" to Summer reads');
      final entry = controller.shelfSection(summerRef).single;
      expect(entry.currentPage, 120);
      expect(entry.status, ReadingStatus.reading);
      expect(userBooks.shelfChanges.single.shelfId, summer.id);
      expect(events.logged, isEmpty);
    });

    test('move to the custom shelf it is already on fails', () async {
      final controller = controllerWith(
        [_entry(_dune, shelfId: summer.id)],
        shelves: [summer],
      );
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'Summer reads');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already on Summer reads.');
    });

    test(
      'moving back to the built-in shelf of the same status keeps the page',
      () async {
        final controller = controllerWith(
          [_entry(_dune, page: 120, shelfId: summer.id)],
          shelves: [summer],
        );
        await controller.load();

        final result = await controller.moveToShelf('Dune', 'reading');

        expect(result.success, isTrue);
        expect(controller.inProgress.single.currentPage, 120);
        expect(userBooks.shelfChanges.single.shelfId, isNull);
      },
    );

    test('moving off a custom shelf to another status applies that shelf\'s '
        'rules', () async {
      final controller = controllerWith(
        [_entry(_dune, page: 120, shelfId: summer.id)],
        shelves: [summer],
      );
      await controller.load();

      await controller.moveToShelf('Dune', 'finished');
      await Future<void>.delayed(Duration.zero);

      expect(controller.finished.single.currentPage, 400);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.finish, title: 'Dune'),
      ]);
    });

    test('move adds a book not on the shelf yet straight to a custom shelf, '
        'as a to-read book', () async {
      final controller = controllerWith([], shelves: [summer]);
      await controller.load();

      final result = await controller.moveToShelf('Dune', 'summer reads');

      expect(result.success, isTrue);
      expect(result.message, 'Added "Dune" to Summer reads');
      final entry = controller.shelfSection(summerRef).single;
      expect(entry.status, ReadingStatus.toBeRead);
    });

    test('finish leaves a book on its custom shelf', () async {
      final controller = controllerWith(
        [_entry(_dune, page: 120, shelfId: summer.id)],
        shelves: [summer],
      );
      await controller.load();

      await controller.finishBook('Dune');

      final entry = controller.shelfSection(summerRef).single;
      expect(entry.isFinished, isTrue);
    });

    test(
      'an unquoted move splits on the longest shelf name that exists',
      () async {
        const summerReading = Shelf(id: 'shelf-sr', name: 'summer reading');
        final controller = controllerWith(
          [_entry(_dune, page: 120)],
          shelves: [summerReading],
        );
        await controller.load();

        final result = await controller.moveToShelfUnsplit(
          'dune summer reading',
        );

        expect(result.success, isTrue);
        expect(result.message, 'Moved "Dune" to summer reading');
        expect(
          controller.splitTrailingShelf('dune reading')?.shelfName,
          'reading',
        );
        expect(controller.splitTrailingShelf('reading'), isNull);
      },
    );

    test(
      'an unquoted move naming no shelf fails with the make command',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        await controller.load();

        final result = await controller.moveToShelfUnsplit('dune later');

        expect(result.success, isFalse);
        expect(result.message, contains('make shelf later'));
      },
    );

    test(
      'dragging onto a custom shelf moves the book there and orders it',
      () async {
        final controller = controllerWith(
          [
            _entry(_dune, page: 120),
            _entry(_circe, page: 20, shelfId: summer.id),
          ],
          shelves: [summer],
        );
        await controller.load();

        final result = await controller.moveBook(
          'progress-book-1',
          summerRef,
          0,
        );

        expect(result.success, isTrue);
        expect(controller.shelfSection(summerRef).map((e) => e.book.title), [
          'Dune',
          'Circe',
        ]);
        expect(controller.shelfSection(summerRef).first.currentPage, 120);
        expect(userBooks.savedOrders.single, [
          'progress-book-1',
          'progress-book-3',
        ]);
      },
    );
  });

  group('tags and comments commands', () {
    test('add tag tags a book on the shelf with a tag made first', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
      await controller.makeTag('sci-fi', isPro: true);

      final result = await controller.addTag('dune', 'sci-fi');

      expect(result.success, isTrue);
      expect(result.message, 'Tagged "Dune" as sci-fi');
      expect(notes.tags.single, ('progress-book-1', 'sci-fi'));
    });

    test('add tag adds a book that is not on the shelf yet, to read, then '
        'tags it', () async {
      final controller = controllerWith([]);
      await controller.load();
      await controller.makeTag('sci-fi', isPro: true);

      final result = await controller.addTag('Dune', 'sci-fi');

      expect(result.success, isTrue);
      expect(result.addedToLibrary, isTrue);
      expect(result.message, 'Added "Dune" to read and tagged it sci-fi');
      expect(controller.toBeRead.single.book.title, 'Dune');
      expect(notes.tags.single.$2, 'sci-fi');
    });

    test('add tag with a tag that was never made adds nothing', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.addTag('Dune', 'sci-fi');

      expect(result.success, isFalse);
      expect(controller.books, isEmpty);
      expect(userBooks.rows, isEmpty);
    });

    test('add tag reports an invalid tag without writing', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addTag('Dune', 'x' * 41);

      expect(result.success, isFalse);
      expect(result.message, 'Max 40 characters.');
    });

    test('add tag surfaces a repository failure', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
      await controller.makeTag('sci-fi', isPro: true);
      notes.failure = const NetworkException("You're offline");

      final result = await controller.addTag('Dune', 'sci-fi');

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
    });

    test('a quoted comment goes to the named book', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addComment(
        'loved the ending',
        title: 'Dune',
      );

      expect(result.success, isTrue);
      expect(notes.comments.single, ('progress-book-1', 'loved the ending'));
    });

    test(
      'an unquoted comment is split on the longest trailing title',
      () async {
        final controller = controllerWith([
          _entry(_dune),
          _entry(_duneMessiah),
        ]);
        await controller.load();

        final result = await controller.addComment(
          'even better than the first dune messiah',
        );

        expect(result.success, isTrue);
        expect(result.message, 'Commented on "Dune Messiah"');
        expect(notes.comments.single, (
          'progress-book-4',
          'even better than the first',
        ));
      },
    );

    test(
      'an unquoted comment with no book on the shelf fails with a hint',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        await controller.load();

        final result = await controller.addComment('great read circe');

        expect(result.success, isFalse);
        expect(result.message, contains('add comment "text" <book>'));
        expect(notes.comments, isEmpty);
      },
    );

    test(
      'splitTrailingTitle always leaves at least one word of comment',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        await controller.load();

        expect(controller.splitTrailingTitle('Dune'), isNull);
        expect(controller.splitTrailingTitle('wow Dune')?.prefix, 'wow');
      },
    );
  });

  group('detail page by-id commands', () {
    test('updateProgressById writes the page for exactly that row', () async {
      final controller = controllerWith([
        _entry(_dune, page: 10),
        _entry(_duneMessiah, page: 10),
      ]);
      await controller.load();

      final result = await controller.updateProgressById('progress-book-4', 50);

      expect(result.success, isTrue);
      expect(controller.findById('progress-book-4')!.currentPage, 50);
      expect(controller.findById('progress-book-1')!.currentPage, 10);
    });

    test('updateProgressById validates the page', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgressById(
        'progress-book-1',
        999,
      );

      expect(result.success, isFalse);
      expect(result.message, '"Dune" only has 400 pages.');
    });

    test('pageForPercent is the one percent-to-page rule', () {
      final dune = _entry(_dune);
      expect(LibraryController.pageForPercent(dune, 50).page, 200);
      expect(LibraryController.pageForPercent(dune, 101).page, isNull);
      expect(LibraryController.pageForPercent(dune, double.nan).page, isNull);
      expect(
        LibraryController.pageForPercent(_entry(_untitledLength), 50).failure,
        contains("don't know how many pages"),
      );
    });

    test('rateBookById refuses an unfinished book', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.rateBookById('progress-book-1', 4);

      expect(result.success, isFalse);
      expect(result.message, 'Finish "Dune" to rate it.');
    });

    group('setOwnedEdition', () {
      const shortEbook = BookEdition(
        id: 'edition-short',
        googleBooksId: 'g-short',
        title: 'Dune',
        author: 'Frank Herbert',
        format: EditionFormat.ebook,
        publisher: 'Penguin',
        pageCount: 200,
        coverUrl: 'https://example.test/short.jpg',
      );
      const noLength = BookEdition(
        id: 'edition-unknown',
        googleBooksId: 'g-unknown',
        title: 'Dune',
        author: 'Frank Herbert',
        format: EditionFormat.physical,
      );

      test(
        'makes the edition the book for this reader, keeping their place',
        () async {
          final controller = controllerWith([_entry(_dune, page: 100)]);
          await controller.load();

          final result = await controller.setOwnedEdition(
            'progress-book-1',
            shortEbook,
          );

          final entry = controller.findById('progress-book-1')!;
          expect(result.success, isTrue);
          // 100 of 400 is 25%; 25% of 200 is page 50.
          expect(entry.currentPage, 50);
          expect(entry.pageCount, 200);
          expect(entry.completion, closeTo(0.25, 0.001));
          expect(entry.displayBook.coverUrl, 'https://example.test/short.jpg');
          expect(entry.displayBook.publisher, 'Penguin');
          // The work itself is untouched — titles still match commands.
          expect(entry.book.pageCount, 400);
          expect(entry.displayBook.title, 'Dune');
          expect(result.message, 'Saved your edition — now page 50 of 200');
          expect(userBooks.ownedEditions.single, (
            'progress-book-1',
            'edition-short',
            50,
          ));
        },
      );

      test('clearing it goes back to the work and rescales again', () async {
        final controller = controllerWith([_entry(_dune, page: 100)]);
        await controller.load();
        await controller.setOwnedEdition('progress-book-1', shortEbook);

        final result = await controller.setOwnedEdition(
          'progress-book-1',
          null,
        );

        final entry = controller.findById('progress-book-1')!;
        expect(result.message, 'Cleared your edition — now page 100 of 400');
        expect(entry.currentPage, 100);
        expect(entry.ownedEdition, isNull);
        expect(entry.displayBook.coverUrl, _dune.coverUrl);
      });

      test('a finished book stays finished at the new last page', () async {
        final controller = controllerWith([
          _entry(_dune, page: 400, finished: true),
        ]);
        await controller.load();

        final result = await controller.setOwnedEdition(
          'progress-book-1',
          shortEbook,
        );

        final entry = controller.findById('progress-book-1')!;
        expect(entry.currentPage, 200);
        expect(entry.isFinished, isTrue);
        expect(result.message, 'Saved your edition');
      });

      test(
        'an edition without a length keeps the work length and page',
        () async {
          final controller = controllerWith([_entry(_dune, page: 100)]);
          await controller.load();

          await controller.setOwnedEdition('progress-book-1', noLength);

          final entry = controller.findById('progress-book-1')!;
          expect(entry.currentPage, 100);
          expect(entry.pageCount, 400);
          // No cover of its own: the work's cover stays rather than a blank.
          expect(entry.displayBook.coverUrl, _dune.coverUrl);
          // No publisher of its own: nothing, rather than the work's.
          expect(entry.displayBook.publisher, isNull);
        },
      );

      test('rolls back the edition and the page on failure', () async {
        final controller = controllerWith([_entry(_dune, page: 100)]);
        await controller.load();
        userBooks.failure = const RemoteDataException('nope');

        final result = await controller.setOwnedEdition(
          'progress-book-1',
          shortEbook,
        );

        final entry = controller.findById('progress-book-1')!;
        expect(result.success, isFalse);
        expect(entry.progress.ownedEditionId, isNull);
        expect(entry.ownedEdition, isNull);
        expect(entry.currentPage, 100);
        expect(entry.pageCount, 400);
      });

      test('refuses an edition that was never cached', () async {
        final controller = controllerWith([_entry(_dune, page: 100)]);
        await controller.load();

        final result = await controller.setOwnedEdition(
          'progress-book-1',
          const BookEdition(
            googleBooksId: 'g',
            title: 'Dune',
            author: 'Frank Herbert',
            format: EditionFormat.ebook,
          ),
        );

        expect(result.success, isFalse);
        expect(userBooks.ownedEditions, isEmpty);
      });

      test('progress commands use the owned edition length', () async {
        final controller = controllerWith([_entry(_dune, page: 100)]);
        await controller.load();
        await controller.setOwnedEdition('progress-book-1', shortEbook);

        final tooFar = await controller.updateProgress('Dune', 300);
        expect(tooFar.message, '"Dune" only has 200 pages.');

        final half = await controller.updateProgressByPercent('Dune', 50);
        expect(half.success, isTrue);
        expect(controller.findById('progress-book-1')!.currentPage, 100);
      });

      test('a later shelf write keeps the edition on the local row', () async {
        final controller = controllerWith([_entry(_dune, page: 100)]);
        await controller.load();
        await controller.setOwnedEdition('progress-book-1', shortEbook);

        await controller.updateProgress('Dune', 120);

        expect(
          controller.findById('progress-book-1')!.displayBook.coverUrl,
          'https://example.test/short.jpg',
        );
      });
    });
  });

  group('advanceProgress', () {
    test('adds the pages to the page already saved', () async {
      final controller = controllerWith([_entry(_dune, page: 100)]);
      await controller.load();

      final result = await controller.advanceProgress('dune', 24);

      expect(result.success, isTrue);
      expect(result.message, 'On page 124 of "Dune"');
      expect(controller.inProgress.single.currentPage, 124);
    });

    test(
      'reading past the end finishes the book rather than failing',
      () async {
        final controller = controllerWith([_entry(_dune, page: 390)]);
        await controller.load();

        final result = await controller.advanceProgress('dune', 40);

        expect(result.success, isTrue);
        expect(result.message, 'Finished "Dune"');
        expect(
          controller.section(ReadingStatus.finished).single.currentPage,
          400,
        );
      },
    );

    test('a book not on the shelf starts from page 0', () async {
      final controller = controllerWith(const []);
      await controller.load();

      final result = await controller.advanceProgress('dune', 24);

      expect(result.success, isTrue);
      expect(controller.inProgress.single.currentPage, 24);
    });

    test('no pages at all is refused', () async {
      final controller = controllerWith([_entry(_dune, page: 100)]);
      await controller.load();

      final result = await controller.advanceProgress('dune', 0);

      expect(result.success, isFalse);
      expect(controller.inProgress.single.currentPage, 100);
    });
  });

  group('updateProgress', () {
    test('applies the new page and reports it', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgress('dune', 120);

      expect(result.success, isTrue);
      expect(result.message, 'On page 120 of "Dune"');
      expect(controller.inProgress.single.currentPage, 120);
      expect(controller.inProgress.single.completion, closeTo(0.3, 0.001));

      await Future<void>.delayed(Duration.zero);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.update, title: 'Dune'),
      ]);
      expect(
        events.logged.single.value,
        120,
        reason: 'the streak journal reads this back as "up to page 120"',
      );
    });

    test('backdates the reading event when given a date', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      final result = await controller.updateProgress(
        'Dune',
        120,
        loggedAt: yesterday,
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(events.logged.single.occurredAt, yesterday.toUtc());
    });

    test('refuses a future date without writing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final result = await controller.updateProgress(
        'Dune',
        120,
        loggedAt: tomorrow,
      );

      expect(result.success, isFalse);
      expect(result.message, 'Date is in the future.');
      expect(controller.inProgress.single.currentPage, 10);
      expect(events.logged, isEmpty);
    });

    test('notifies synchronously enough for the UI to redraw before the '
        'write completes', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final pending = controller.updateProgress('Dune', 200);
      // The optimistic local write has already happened here, before the
      // repository future resolves — this is what makes the shelf update
      // without a refresh.
      expect(controller.inProgress.single.currentPage, 200);

      await pending;
      expect(controller.inProgress.single.currentPage, 200);
    });

    test('reaching the last page moves the book to Finished', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgress('Dune', 400);

      expect(result.success, isTrue);
      expect(controller.inProgress, isEmpty);
      expect(controller.finished.single.book.title, 'Dune');
      expect(controller.finished.single.completion, 1);

      await Future<void>.delayed(Duration.zero);
      expect(
        events.loggedTypesAndTitles,
        [(type: ReadingEventType.finish, title: 'Dune')],
        reason:
            'reaching the last page via update reads as a finish, not an update',
      );
      expect(
        events.logged.single.value,
        isNull,
        reason: 'a finish has no page number to journal',
      );
    });

    test('rejects a page past the end without writing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgress('Dune', 999);

      expect(result.success, isFalse);
      expect(result.message, '"Dune" only has 400 pages.');
      expect(userBooks.saves, 0);
      expect(controller.inProgress.single.currentPage, 10);
    });

    test('rejects a negative page without writing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgress('Dune', -5);

      expect(result.success, isFalse);
      expect(userBooks.saves, 0);
    });

    test('accepts any page when the total is unknown, and shows no '
        'percentage', () async {
      final controller = controllerWith([_entry(_untitledLength, page: 3)]);
      await controller.load();

      final result = await controller.updateProgress('Pale Fire', 900);

      expect(result.success, isTrue);
      expect(controller.inProgress.single.completion, isNull);
      expect(controller.inProgress.single.isFinished, isFalse);
    });

    test('a book that isn\'t on the shelf is started, then updated', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.updateProgress('Dune', 40);
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(result.addedToLibrary, isTrue);
      expect(controller.inProgress.single.currentPage, 40);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.start, title: 'Dune'),
        (type: ReadingEventType.update, title: 'Dune'),
      ]);
    });

    test('a page past the end refuses before anything is added', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.updateProgress('Dune', 900);

      expect(result.success, isFalse);
      expect(result.message, '"Dune" only has 400 pages.');
      expect(controller.books, isEmpty);
    });

    test('rolls the optimistic update back when the write fails', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.updateProgress('Dune', 120);

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(
        controller.inProgress.single.currentPage,
        10,
        reason: 'screen must not show a page that never persisted',
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        events.loggedTypesAndTitles,
        isEmpty,
        reason: 'a rolled-back write must not log an event',
      );
    });
  });

  group('updateProgressByPercent', () {
    test('resolves a percentage to a page against the total', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgressByPercent('Dune', 50);

      expect(result.success, isTrue);
      expect(controller.inProgress.single.currentPage, 200);
    });

    test('100% finishes the book, same as reaching the last page', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgressByPercent('Dune', 100);

      expect(result.success, isTrue);
      expect(controller.finished.single.book.title, 'Dune');
    });

    test('rejects a percentage outside 0-100 without writing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgressByPercent('Dune', 120);

      expect(result.success, isFalse);
      expect(userBooks.saves, 0);
      expect(controller.inProgress.single.currentPage, 10);
    });

    test('refuses a percentage when the total page count is unknown', () async {
      final controller = controllerWith([_entry(_untitledLength, page: 3)]);
      await controller.load();

      final result = await controller.updateProgressByPercent('Pale Fire', 50);

      expect(result.success, isFalse);
      expect(userBooks.saves, 0);
    });
  });

  group('finishBook', () {
    test('a book that isn\'t on the shelf is added straight to finished, '
        'backdated when a date is given', () async {
      final controller = controllerWith([]);
      await controller.load();
      final lastWeek = DateTime.now().subtract(const Duration(days: 7));

      final result = await controller.finishBook('Dune', loggedAt: lastWeek);
      await Future<void>.delayed(Duration.zero);

      expect(result.success, isTrue);
      expect(result.addedToLibrary, isTrue);
      expect(result.message, 'Added "Dune" as finished');
      final finished = controller.finished.single;
      expect(finished.currentPage, 400);
      expect(finished.progress.finishedAt, lastWeek.toUtc());
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.finish, title: 'Dune'),
      ]);
    });

    test('moves the book to Finished and fills its progress bar', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.finishBook('Dune');

      expect(result.success, isTrue);
      expect(controller.inProgress, isEmpty);
      expect(controller.finished.single.currentPage, 400);
      expect(controller.finished.single.completion, 1);

      await Future<void>.delayed(Duration.zero);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.finish, title: 'Dune'),
      ]);
    });

    test(
      'backdates both the reading event and the book\'s own finishedAt',
      () async {
        final controller = controllerWith([_entry(_dune, page: 10)]);
        await controller.load();
        final yesterday = DateTime.now().subtract(const Duration(days: 1));

        final result = await controller.finishBook('Dune', loggedAt: yesterday);
        await Future<void>.delayed(Duration.zero);

        expect(result.success, isTrue);
        expect(events.logged.single.occurredAt, yesterday.toUtc());
        expect(
          controller.finished.single.progress.finishedAt,
          yesterday.toUtc(),
        );
      },
    );

    test('refuses a future date without writing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final result = await controller.finishBook('Dune', loggedAt: tomorrow);

      expect(result.success, isFalse);
      expect(result.message, 'Date is in the future.');
      expect(controller.finished, isEmpty);
      expect(events.logged, isEmpty);
    });

    test('finishes a book with no known length', () async {
      final controller = controllerWith([_entry(_untitledLength, page: 12)]);
      await controller.load();

      await controller.finishBook('Pale Fire');

      expect(controller.finished.single.isFinished, isTrue);
      expect(controller.finished.single.completion, 1);
    });

    test('finishing an already-finished book fails instead of '
        're-confirming it', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.finishBook('Dune');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already finished.');
    });
  });

  group('restartBook', () {
    test('puts a finished book back on the reading shelf at page 0', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.restartBook('Dune');

      expect(result.success, isTrue);
      expect(result.message, 'Restarted "Dune"');
      expect(controller.finished, isEmpty);
      expect(controller.inProgress.single.currentPage, 0);
      expect(controller.inProgress.single.rereadCount, 1);

      await Future<void>.delayed(Duration.zero);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.restart, title: 'Dune'),
      ]);
    });

    test('bumps rereadCount again on a second restart', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      await controller.restartBook('Dune');
      await controller.finishBook('Dune');
      final result = await controller.restartBook('Dune');

      expect(result.success, isTrue);
      expect(controller.inProgress.single.rereadCount, 2);
    });

    test('refuses a book that has never been finished', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.restartBook('Dune');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" isn\'t finished.');
      expect(userBooks.restarts, isEmpty);
    });

    test('explains itself when the book was never started', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.restartBook('Dune');

      expect(result.success, isFalse);
    });

    test('refuses a future date without writing', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final result = await controller.restartBook('Dune', loggedAt: tomorrow);

      expect(result.success, isFalse);
      expect(controller.finished, isNotEmpty);
      expect(userBooks.restarts, isEmpty);
    });

    test('rolls back local state when the write fails', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.restartBook('Dune');

      expect(result.success, isFalse);
      expect(controller.finished.single.currentPage, 400);
      expect(controller.finished.single.rereadCount, 0);
    });
  });

  group('rateBook', () {
    test('rates a finished book and shows the star', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.rateBook('dune', 4.5);

      expect(result.success, isTrue);
      expect(result.message, 'Rated "Dune" 4.5 stars');
      expect(controller.finished.single.rating, 4.5);

      await Future<void>.delayed(Duration.zero);
      expect(events.loggedTypesAndTitles, [
        (type: ReadingEventType.rate, title: 'Dune'),
      ]);
      expect(
        events.logged.single.value,
        4.5,
        reason: 'the streak journal reads this back as "rated Dune 4.5 stars"',
      );
    });

    test('rounds a rating to the nearest half star before saving', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.rateBook('Dune', 4.3);

      expect(result.success, isTrue);
      expect(
        result.message,
        'Rated "Dune" 4.5 stars',
        reason: '4.3 is closer to 4.5 than 4.0',
      );
      expect(controller.finished.single.rating, 4.5);
    });

    test('formats a rounded whole rating without a trailing .0', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.rateBook('Dune', 4.2);

      expect(
        result.message,
        'Rated "Dune" 4 stars',
        reason: '4.2 rounds down to 4.0',
      );
      expect(controller.finished.single.rating, 4.0);
    });

    test('refuses to rate a book still in progress', () async {
      final controller = controllerWith([_entry(_dune, page: 100)]);
      await controller.load();

      final result = await controller.rateBook('Dune', 5);

      expect(result.success, isFalse);
      expect(result.message, 'Finish "Dune" to rate it.');
      expect(controller.inProgress.single.rating, isNull);
      expect(userBooks.rates, 0);
    });

    test(
      'a book that isn\'t on the shelf is added as finished, then rated',
      () async {
        final controller = controllerWith([]);
        await controller.load();

        final result = await controller.rateBook('Dune', 4.5);

        expect(result.success, isTrue);
        expect(result.addedToLibrary, isTrue);
        expect(result.message, 'Added "Dune" as finished, rated 4.5 stars');
        expect(controller.finished.single.rating, 4.5);
      },
    );

    test('an out-of-range rating refuses before anything is added', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.rateBook('Dune', 9);

      expect(result.success, isFalse);
      expect(controller.books, isEmpty);
    });

    test('rejects a rating outside 0.5-5 without writing', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final tooHigh = await controller.rateBook('Dune', 6);
      final zero = await controller.rateBook('Dune', 0);

      expect(tooHigh.success, isFalse);
      expect(zero.success, isFalse);
      expect(userBooks.rates, 0);
    });

    test('rolls back when the write fails', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.rateBook('Dune', 4);

      expect(result.success, isFalse);
      expect(
        controller.finished.single.rating,
        isNull,
        reason: 'screen must not show a rating that never persisted',
      );
    });
  });

  group('start and dates', () {
    test('start on a book queued to read moves it to reading and stamps the '
        'start date', () async {
      final controller = controllerWith([
        _entry(_dune, status: ReadingStatus.toBeRead),
      ]);
      await controller.load();
      final monday = DateTime.now().subtract(const Duration(days: 3));

      final result = await controller.startBook('Dune', loggedAt: monday);

      expect(result.success, isTrue);
      expect(controller.inProgress.single.progress.startedAt, monday.toUtc());
      expect(userBooks.shelfChanges.single.startedAt, monday.toUtc());
    });

    test('a new book started with a date keeps it as its start date', () async {
      final controller = controllerWith([]);
      await controller.load();
      final monday = DateTime.now().subtract(const Duration(days: 3));

      await controller.startBook('Dune', loggedAt: monday);

      expect(controller.inProgress.single.progress.startedAt, monday.toUtc());
    });

    test('setDates saves a valid start and finish', () async {
      final started = DateTime(2026, 1, 2);
      final finished = DateTime(2026, 2, 3);
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.setDates(
        'progress-book-1',
        startedAt: started,
        finishedAt: finished,
      );

      expect(result.success, isTrue);
      expect(userBooks.savedDates.single, (
        'progress-book-1',
        started,
        finished,
      ));
      expect(controller.finished.single.progress.startedAt, started.toUtc());
    });

    test('setDates refuses the impossible without writing', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
        _entry(_circe, page: 10),
      ]);
      await controller.load();
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      final future = await controller.setDates(
        'progress-book-1',
        startedAt: tomorrow,
      );
      expect(future.message, 'Date is in the future.');

      await controller.setDates(
        'progress-book-1',
        startedAt: DateTime(2026, 3, 1),
      );
      final backwards = await controller.setDates(
        'progress-book-1',
        finishedAt: DateTime(2026, 2, 1),
      );
      expect(backwards.message, 'Finish is before start.');

      final notFinished = await controller.setDates(
        'progress-book-3',
        finishedAt: DateTime(2026, 2, 1),
      );
      expect(notFinished.message, 'Not finished yet.');

      expect(userBooks.savedDates, hasLength(1));
    });

    test('setDates rolls back when the write fails', () async {
      final started = DateTime.utc(2026, 1, 2);
      final controller = controllerWith([
        LibraryBook(
          book: _dune,
          progress: UserBook(
            id: 'progress-book-1',
            bookId: _dune.id,
            currentPage: 10,
            status: ReadingStatus.reading,
            startedAt: started,
          ),
        ),
      ]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.setDates(
        'progress-book-1',
        startedAt: DateTime(2026, 1, 5),
      );

      expect(result.success, isFalse);
      expect(controller.inProgress.single.progress.startedAt, started);
    });
  });

  group('remove commands', () {
    test('resolveRemoval splits an unquoted name from a title, longest '
        'collection name first', () async {
      final controller = controllerWith(
        [_entry(_dune)],
        shelves: const [
          Shelf(id: 'shelf-1', name: 'summer'),
          Shelf(id: 'shelf-2', name: 'summer reads'),
        ],
      );
      await controller.load();

      final off = controller.resolveRemoval(
        CollectionKind.shelves,
        argument: 'summer reads dune',
      );
      expect(off.removal, isA<RemoveFromCollection>());
      expect((off.removal! as RemoveFromCollection).title, 'dune');
      expect(off.removal!.name, 'summer reads');

      final unmake = controller.resolveRemoval(
        CollectionKind.shelves,
        argument: 'Summer Reads',
      );
      expect(unmake.removal, isA<UnmakeCollection>());
      expect((unmake.removal! as UnmakeCollection).id, 'shelf-2');

      final builtIn = controller.resolveRemoval(
        CollectionKind.shelves,
        argument: 'reading',
      );
      expect(builtIn.failure, contains('built-in shelf'));

      final unknown = controller.resolveRemoval(
        CollectionKind.tags,
        argument: 'nope dune',
      );
      expect(unknown.failure, 'No tag called "nope".');
    });

    test(
      'remove shelf with a book takes it off the shelf, progress kept',
      () async {
        final controller = controllerWith(
          [_entry(_dune, page: 120, shelfId: 'shelf-1')],
          shelves: const [Shelf(id: 'shelf-1', name: 'summer')],
        );
        await controller.load();

        final result = await controller.removeFromShelf('Dune', 'summer');

        expect(result.success, isTrue);
        expect(controller.inProgress.single.currentPage, 120);
        expect(controller.inProgress.single.shelfId, isNull);
      },
    );

    test('remove shelf with no book unmakes it and returns its books to '
        'their own shelves', () async {
      final controller = controllerWith(
        [_entry(_dune, page: 120, shelfId: 'shelf-1')],
        shelves: const [Shelf(id: 'shelf-1', name: 'summer')],
      );
      await controller.load();

      final result = await controller.deleteShelf('shelf-1');

      expect(result.success, isTrue);
      expect(collections.deletedShelves, ['shelf-1']);
      expect(controller.shelves, isEmpty);
      expect(controller.inProgress.single.shelfId, isNull);
    });

    test(
      'remove tag takes a tag off a book, and refuses one it lacks',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        await controller.load();
        await controller.makeTag('sci-fi', isPro: true);
        await controller.addTag('Dune', 'sci-fi');

        final removed = await controller.removeTag('Dune', 'Sci-Fi');
        expect(removed.success, isTrue);
        expect(notes.removedTags, ['book-tag-1']);

        await controller.makeTag('cosy', isPro: true);
        final missing = await controller.removeTag('Dune', 'cosy');
        expect(missing.message, '"Dune" isn\'t tagged cosy.');
      },
    );

    test('remove tag with no book unmakes the tag', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
      await controller.makeTag('sci-fi', isPro: true);
      final tag = controller.findTag('sci-fi')!;

      final result = await controller.deleteTag(tag.id);

      expect(result.success, isTrue);
      expect(controller.tags, isEmpty);
    });

    test('by id, filing and unfiling touch exactly that row when two books '
        'share a title', () async {
      const otherDune = Book(
        id: 'book-dune-2',
        googleBooksId: 'gb-dune-2',
        title: 'Dune',
        author: 'Someone Else',
      );
      // Most recently updated first — a title match would pick this one.
      final controller = controllerWith([_entry(otherDune), _entry(_dune)]);
      await controller.load();
      await controller.makeSeries('dune', isPro: true);

      final filed = await controller.addToSeriesById(
        'progress-book-1',
        'dune',
        position: 1,
      );
      expect(filed.success, isTrue);
      expect(controller.findById('progress-book-1')!.seriesId, isNotNull);
      expect(controller.findById('progress-book-dune-2')!.seriesId, isNull);

      // No series named: out of whatever series it's in.
      final out = await controller.removeFromSeriesById('progress-book-1');
      expect(out.success, isTrue);
      expect(controller.findById('progress-book-1')!.seriesId, isNull);

      final again = await controller.removeFromSeriesById('progress-book-1');
      expect(again.success, isFalse);
      expect(again.message, '"Dune" isn\'t in a series.');
    });

    test(
      'remove series takes a book out, and unmaking clears every filing',
      () async {
        final controller = controllerWith([
          _entry(_dune),
          _entry(_duneMessiah),
        ]);
        await controller.load();
        await controller.makeSeries('dune', isPro: true);
        await controller.addToSeries('Dune', 'dune', position: 1);
        await controller.addToSeries('Dune Messiah', 'dune', position: 2);

        final out = await controller.removeFromSeries(
          'Dune Messiah',
          seriesName: 'dune',
        );
        expect(out.success, isTrue);
        expect(controller.bookForTitleEntry('Dune Messiah')!.seriesId, isNull);
        expect(series.cleared, ['progress-book-4']);

        final wrong = await controller.removeFromSeries(
          'Dune Messiah',
          seriesName: 'dune',
        );
        expect(wrong.success, isFalse);

        final id = controller.findSeries('dune')!.id;
        final unmade = await controller.deleteSeries(id);
        expect(unmade.success, isTrue);
        expect(controller.bookForTitleEntry('Dune')!.seriesId, isNull);
        expect(controller.bookForTitleEntry('Dune')!.seriesPosition, isNull);
      },
    );

    test('remove comment finds the named comment, or the latest', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
      notes.storedComments.addAll([
        BookComment(
          id: 'c1',
          userBookId: 'progress-book-1',
          body: 'slow start',
          createdAt: DateTime(2026, 1, 1),
        ),
        BookComment(
          id: 'c2',
          userBookId: 'progress-book-1',
          body: 'loved the ending, truly',
          createdAt: DateTime(2026, 2, 1),
        ),
      ]);

      final latest = await controller.resolveCommentRemoval(argument: 'dune');
      expect(latest.comment!.id, 'c2');

      final named = await controller.resolveCommentRemoval(
        argument: 'slow start dune',
      );
      expect(named.comment!.id, 'c1');

      final prefix = await controller.resolveCommentRemoval(
        title: 'Dune',
        text: 'LOVED the ending',
      );
      expect(prefix.comment!.id, 'c2');

      final none = await controller.resolveCommentRemoval(
        title: 'Dune',
        text: 'never said this',
      );
      expect(none.failure, contains('no comment like'));

      final result = await controller.deleteComment(
        latest.entry!,
        latest.comment!,
      );
      expect(result.success, isTrue);
      expect(notes.deletedComments, ['c2']);
    });

    test('the "+" panel removes a book by id', () async {
      final controller = controllerWith([_entry(_dune), _entry(_circe)]);
      await controller.load();

      final result = await controller.deleteBookById('progress-book-3');

      expect(result.success, isTrue);
      expect(controller.books.single.book.title, 'Dune');
    });
  });

  group('import baseline', () {
    test('load reads the import date', () async {
      final controller = controllerWith([]);
      final stamp = DateTime.utc(2026, 9, 1);
      userBooks.importedAt = stamp;

      await controller.load();

      expect(controller.importedAt, stamp);
    });
  });

  group('deleteBook', () {
    test('removes the book from the shelf', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.deleteBook('dune');

      expect(result.success, isTrue);
      expect(result.message, 'Removed "Dune"');
      expect(controller.inProgress, isEmpty);
      expect(controller.finished, isEmpty);
      expect(userBooks.deletedIds, ['progress-book-1']);

      await Future<void>.delayed(Duration.zero);
      expect(
        events.clearedTitles,
        ['Dune'],
        reason: 'deleting the book clears its journal history too',
      );
      expect(
        events.loggedTypesAndTitles,
        isEmpty,
        reason:
            'no new event is logged for a delete — there is nothing left'
            ' to journal',
      );
    });

    test('broadcasts the title on clearedTitles once cleared', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      final broadcast = <String>[];
      controller.clearedTitles.listen(broadcast.add);

      await controller.deleteBook('Dune');
      await Future<void>.delayed(Duration.zero);

      expect(
        broadcast,
        ['Dune'],
        reason:
            'an already-open journal listens for this to drop the '
            "book's lines without a reload",
      );
    });

    test('removes it immediately, before the delete persists', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final pending = controller.deleteBook('Dune');
      // The optimistic local removal has already happened here, before
      // the repository future resolves.
      expect(controller.inProgress, isEmpty);

      await pending;
      expect(controller.inProgress, isEmpty);
    });

    test('explains itself when the book was never started', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.deleteBook('Neuromancer');

      expect(result.success, isFalse);
      expect(result.message, contains('start Neuromancer'));
      expect(userBooks.deletes, 0);
    });

    test('restores the book when the delete fails to persist', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.deleteBook('Dune');

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(
        controller.inProgress.single.book.title,
        'Dune',
        reason: 'screen must not lose a book that never actually deleted',
      );
    });

    test('leaves the finished book untouched by an unrelated delete', () async {
      final controller = controllerWith([
        _entry(_dune, page: 10),
        _entry(_untitledLength, finished: true),
      ]);
      await controller.load();

      await controller.deleteBook('Dune');

      expect(controller.inProgress, isEmpty);
      expect(controller.finished.single.book.title, 'Pale Fire');
    });
  });

  group('audit regressions', () {
    test('deleting by id removes exactly that row when two books share a '
        'title', () async {
      const otherDune = Book(
        id: 'book-dune-2',
        googleBooksId: 'gb-dune-2',
        title: 'Dune',
        author: 'Someone Else',
        pageCount: 100,
      );
      // Most recently updated first — a title match would pick this one.
      final controller = controllerWith([
        _entry(otherDune, page: 5),
        _entry(_dune, page: 10),
      ]);
      await controller.load();

      final result = await controller.deleteBookById('progress-book-1');

      expect(result.success, isTrue);
      expect(userBooks.deletedIds, ['progress-book-1']);
      expect(controller.books.single.book.author, 'Someone Else');
    });

    test('an infinite rating is refused instead of throwing', () async {
      final controller = controllerWith([_entry(_dune, finished: true)]);
      await controller.load();

      final byTitle = await controller.rateBook('Dune', double.infinity);
      final byId = await controller.rateBookById('progress-book-1', double.nan);

      expect(byTitle.success, isFalse);
      expect(byTitle.message, 'Rate 0.5–5 stars.');
      expect(byId.success, isFalse);
    });

    test('an infinite percentage is refused instead of throwing', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgressByPercent(
        'Dune',
        double.infinity,
      );

      expect(result.success, isFalse);
      expect(result.message, 'A percentage has to be between 0 and 100.');
    });

    test('starting a book already being read makes no write at all', () async {
      final controller = controllerWith([_entry(_dune, page: 40)]);
      await controller.load();

      final result = await controller.startBook('Dune');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already shelved.');
      expect(userBooks.starts, 0);
      expect(controller.inProgress.single.currentPage, 40);
    });

    test('a load called while one is in flight joins it rather than '
        'returning early', () async {
      final controller = controllerWith([_entry(_dune)]);
      final gate = userBooks.fetchGate = Completer<void>();

      final first = controller.load();
      var secondDone = false;
      final second = controller.load().then((_) => secondDone = true);
      await pumpEventQueue();
      expect(secondDone, isFalse, reason: 'must wait for the real load');

      gate.complete();
      await Future.wait([first, second]);

      expect(userBooks.fetches, 1);
      expect(controller.books.single.book.title, 'Dune');
      expect(controller.hasLoaded, isTrue);
    });

    test('reset waits out a stale in-flight load and loads again', () async {
      final controller = controllerWith([_entry(_dune)]);
      final gate = userBooks.fetchGate = Completer<void>();
      final stale = controller.load();

      // The library is replaced (an import) while that load is out.
      userBooks.rows
        ..clear()
        ..add(_entry(_circe));
      userBooks.fetchGate = null;
      final reset = controller.reset();
      gate.complete();
      await Future.wait([stale, reset]);

      expect(userBooks.fetches, 2);
      expect(controller.books.single.book.title, 'Circe');
    });

    test(
      'an unexpected load error reads as a failed load, not a throw',
      () async {
        final controller = controllerWith([_entry(_dune)]);
        userBooks.fetchError = StateError('bad row');

        await controller.load();

        expect(controller.errorMessage, "Couldn't load library.");
        expect(controller.isLoading, isFalse);
      },
    );

    test(
      'books and sections keep their identity until the shelf changes',
      () async {
        final controller = controllerWith([
          _entry(_dune, page: 10),
          _entry(_circe, finished: true),
        ]);
        await controller.load();

        final books = controller.books;
        final reading = controller.inProgress;
        expect(identical(controller.books, books), isTrue);
        expect(identical(controller.inProgress, reading), isTrue);

        await controller.updateProgress('Dune', 20);

        expect(identical(controller.books, books), isFalse);
        expect(controller.inProgress.single.currentPage, 20);
        expect(
          () => controller.books.add(_entry(_duneMessiah)),
          throwsA(anything),
        );
      },
    );
  });
}

/// Small convenience so a test can arm the repository failure inline.
extension on LibraryController {
  LibraryBook? bookForTitleEntry(String title) => match(title);

  set userBooksFailure(LibraryException failure) {
    (userBooks as FakeUserBookRepository).failure = failure;
  }
}
