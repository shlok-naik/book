import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  @override
  Future<List<LibraryBook>> fetchLibrary() async {
    if (failure != null) throw failure!;
    return List.of(rows);
  }

  @override
  Future<StartOutcome> start(String bookId) async {
    if (failure != null) throw failure!;
    final existing = _statusByBookId[bookId];
    _statusByBookId.putIfAbsent(bookId, () => ReadingStatus.reading);
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: existing ?? ReadingStatus.reading,
      ),
      alreadyExists: existing != null,
    );
  }

  @override
  Future<StartOutcome> addWithStatus(
    String bookId,
    ReadingStatus status, {
    int currentPage = 0,
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
        finishedAt: actual == ReadingStatus.finished
            ? DateTime.now().toUtc()
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
    return UserBook(
      id: userBookId,
      bookId: 'book',
      currentPage: currentPage,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
      finishedAt: finished ? (finishedAt ?? DateTime.now()).toUtc() : null,
    );
  }

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
  /// the half-way failure a drag between sections has to roll back.
  LibraryException? orderFailure;

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

  @override
  Future<BookTag> addTag(String userBookId, String tag) async {
    final clean = BookNotesRepository.validateTag(tag);
    if (failure != null) throw failure!;
    tags.add((userBookId, clean));
    return BookTag(
      id: 'tag-${tags.length}',
      userBookId: userBookId,
      tag: clean,
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
  Future<Book> cache(GoogleBook volume) async => book;
}

LibraryBook _entry(
  Book book, {
  int page = 0,
  bool finished = false,
  ReadingStatus? status,
  double? position,
  double? rating,
}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
      id: 'progress-${book.id}',
      bookId: book.id,
      currentPage: page,
      status:
          status ?? (finished ? ReadingStatus.finished : ReadingStatus.reading),
      shelfPosition: position,
      rating: rating,
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

  LibraryController controllerWith(List<LibraryBook> rows, {Book? cached}) {
    userBooks = FakeUserBookRepository(rows);
    events = FakeReadingEventRepository();
    notes = FakeBookNotesRepository();
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
      expect(second.message, '"Dune" is already on your shelf.');
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
        expect(result.message, "That date hasn't happened yet.");
        expect(controller.inProgress, isEmpty);
        expect(events.logged, isEmpty);
      },
    );
  });

  group('addToShelf', () {
    test(
      'add shelf tbr puts a resolved book on the to-be-read shelf',
      () async {
        final controller = controllerWith([]);
        var notifications = 0;
        controller.addListener(() => notifications++);

        final result = await controller.addToShelf(
          'Dune',
          ReadingStatus.toBeRead,
        );

        expect(result.success, isTrue);
        expect(result.message, 'Added "Dune" to read');
        expect(controller.toBeRead.single.book.title, 'Dune');
        expect(controller.toBeRead.single.currentPage, 0);
        expect(controller.inProgress, isEmpty);
        expect(controller.finished, isEmpty);
        expect(notifications, greaterThan(0));
      },
    );

    test(
      'add shelf finished puts a new book on the finished shelf at 100%',
      () async {
        final controller = controllerWith([]);

        final result = await controller.addToShelf(
          'Dune',
          ReadingStatus.finished,
        );

        expect(result.success, isTrue);
        expect(result.message, 'Added "Dune" as finished');
        final entry = controller.finished.single;
        expect(entry.book.title, 'Dune');
        expect(entry.currentPage, 400, reason: 'the last page — 100%');
        expect(entry.completion, 1);
      },
    );

    test('add shelf reading adds a new book at page 0', () async {
      final controller = controllerWith([]);

      final result = await controller.addToShelf('Dune', ReadingStatus.reading);

      expect(result.success, isTrue);
      expect(result.message, 'Started "Dune"');
      expect(controller.inProgress.single.currentPage, 0);
    });

    test('logs each shelf as its own journal event', () async {
      for (final (status, type) in [
        (ReadingStatus.toBeRead, ReadingEventType.addToBeRead),
        (ReadingStatus.finished, ReadingEventType.finish),
        (ReadingStatus.dnf, ReadingEventType.dnf),
        (ReadingStatus.reading, ReadingEventType.start),
      ]) {
        final controller = controllerWith([]);

        await controller.addToShelf('Dune', status);
        await Future<void>.delayed(Duration.zero);

        expect(events.loggedTypesAndTitles, [(type: type, title: 'Dune')]);
      }
    });

    test('adding a book to the shelf it is already on fails', () async {
      final controller = controllerWith([]);

      await controller.addToShelf('Dune', ReadingStatus.toBeRead);
      final second = await controller.addToShelf(
        'dune',
        ReadingStatus.toBeRead,
      );

      expect(second.success, isFalse);
      expect(second.message, '"Dune" is already on your to-read shelf.');
      expect(controller.toBeRead, hasLength(1));
    });

    test('refuses a book already marked DNF', () async {
      final controller = controllerWith([]);
      await controller.addToShelf('Dune', ReadingStatus.dnf);

      final result = await controller.addToShelf('Dune', ReadingStatus.dnf);

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already marked as DNF.');
    });
  });

  group('shelf changes and their side effects', () {
    test('moving a reading book to finished sets it to 100%', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      final result = await controller.addToShelf(
        'Dune',
        ReadingStatus.finished,
      );

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

      await controller.addToShelf('Pale Fire', ReadingStatus.finished);

      final entry = controller.finished.single;
      expect(entry.currentPage, 80);
      expect(entry.completion, 1);
    });

    test('moving a book to to read resets it to page 0', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      await controller.addToShelf('Dune', ReadingStatus.toBeRead);

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

        await controller.addToShelf('Dune', ReadingStatus.reading);

        final entry = controller.inProgress.single;
        expect(entry.currentPage, 0);
        expect(entry.progress.finishedAt, isNull);
      },
    );

    test('moving a book to DNF keeps the page it reached', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();

      final result = await controller.addToShelf('Dune', ReadingStatus.dnf);

      expect(result.success, isTrue);
      expect(result.message, 'Marked "Dune" as DNF');
      expect(controller.didNotFinish.single.currentPage, 120);
    });

    test('rolls a shelf change back when the write fails', () async {
      final controller = controllerWith([_entry(_dune, page: 120)]);
      await controller.load();
      userBooks.failure = const NetworkException("You're offline");

      final result = await controller.addToShelf('Dune', ReadingStatus.dnf);

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
          ReadingStatus.reading,
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
        await controller.moveBook('progress-book-1', ReadingStatus.reading, 2);

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
        ReadingStatus.reading,
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
        ReadingStatus.finished,
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

      await controller.moveBook('progress-book-1', ReadingStatus.toBeRead, 0);

      expect(controller.toBeRead.single.currentPage, 0);
    });

    test('rolls the whole shelf back if saving the order fails after the shelf '
        'change landed', () async {
      final controller = controllerWith([
        _entry(_dune, page: 120),
        _entry(_circe, finished: true, page: 300),
      ]);
      await controller.load();
      userBooks.orderFailure = const NetworkException("You're offline");

      final result = await controller.moveBook(
        'progress-book-1',
        ReadingStatus.finished,
        0,
      );

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(controller.inProgress.single.currentPage, 120);
      expect(controller.finished.single.book.title, 'Circe');
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

  group('tags and comments commands', () {
    test('add tag tags a book on the shelf', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addTag('dune', 'sci-fi');

      expect(result.success, isTrue);
      expect(result.message, 'Tagged "Dune" sci-fi');
      expect(notes.tags.single, ('progress-book-1', 'sci-fi'));
    });

    test('add tag refuses a book that is not on the shelf', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.addTag('Dune', 'sci-fi');

      expect(result.success, isFalse);
      expect(result.message, contains("isn't on your shelf yet"));
      expect(notes.tags, isEmpty);
    });

    test('add tag reports an invalid tag without writing', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();

      final result = await controller.addTag('Dune', 'x' * 41);

      expect(result.success, isFalse);
      expect(result.message, 'Tags can be at most 40 characters.');
    });

    test('add tag surfaces a repository failure', () async {
      final controller = controllerWith([_entry(_dune)]);
      await controller.load();
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
        expect(result.message, contains('add comment "your comment" <book>'));
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
      expect(result.message, 'Finish "Dune" before rating it.');
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

  group('updateProgress', () {
    test('applies the new page and reports it', () async {
      final controller = controllerWith([_entry(_dune, page: 10)]);
      await controller.load();

      final result = await controller.updateProgress('dune', 120);

      expect(result.success, isTrue);
      expect(result.message, '"Dune" — pg 120');
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
      expect(result.message, "That date hasn't happened yet.");
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

    test('explains itself when the book was never started', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.updateProgress('Neuromancer', 40);

      expect(result.success, isFalse);
      expect(result.message, contains('start Neuromancer'));
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
      expect(result.message, "That date hasn't happened yet.");
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

  group('rateBook', () {
    test('rates a finished book and shows the star', () async {
      final controller = controllerWith([
        _entry(_dune, page: 400, finished: true),
      ]);
      await controller.load();

      final result = await controller.rateBook('dune', 4.5);

      expect(result.success, isTrue);
      expect(result.message, '"Dune" — 4.5★');
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
        '"Dune" — 4.5★',
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

      expect(result.message, '"Dune" — 4★', reason: '4.2 rounds down to 4.0');
      expect(controller.finished.single.rating, 4.0);
    });

    test('refuses to rate a book still in progress', () async {
      final controller = controllerWith([_entry(_dune, page: 100)]);
      await controller.load();

      final result = await controller.rateBook('Dune', 5);

      expect(result.success, isFalse);
      expect(result.message, 'Finish "Dune" before rating it.');
      expect(controller.inProgress.single.rating, isNull);
      expect(userBooks.rates, 0);
    });

    test('explains itself when the book was never started', () async {
      final controller = controllerWith([]);
      await controller.load();

      final result = await controller.rateBook('Neuromancer', 5);

      expect(result.success, isFalse);
      expect(result.message, contains('start Neuromancer'));
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
}

/// Small convenience so a test can arm the repository failure inline.
extension on LibraryController {
  set userBooksFailure(LibraryException failure) {
    (userBooks as FakeUserBookRepository).failure = failure;
  }
}
