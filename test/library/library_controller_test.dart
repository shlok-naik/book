import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
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

  /// Tracks which book ids have already been started, so a second
  /// [start] call can report [StartOutcome.alreadyExists] — mirrors
  /// what the real upsert-then-select does against Supabase.
  final Set<String> _startedBookIds = {};

  @override
  Future<List<LibraryBook>> fetchLibrary() async {
    if (failure != null) throw failure!;
    return List.of(rows);
  }

  @override
  Future<StartOutcome> start(String bookId) async {
    if (failure != null) throw failure!;
    final isNew = _startedBookIds.add(bookId);
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: ReadingStatus.reading,
      ),
      alreadyExists: !isNew,
    );
  }

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
  }) async {
    saves++;
    if (failure != null) throw failure!;
    return UserBook(
      id: userBookId,
      bookId: 'book',
      currentPage: currentPage,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
    );
  }

  @override
  Future<void> delete(String userBookId) async {
    deletes++;
    if (failure != null) throw failure!;
    deletedIds.add(userBookId);
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

LibraryBook _entry(Book book, {int page = 0, bool finished = false}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
      id: 'progress-${book.id}',
      bookId: book.id,
      currentPage: page,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
    ),
  );
}

void main() {
  late FakeUserBookRepository userBooks;

  LibraryController controllerWith(List<LibraryBook> rows, {Book? cached}) {
    userBooks = FakeUserBookRepository(rows);
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

    test('surfaces a failure as a retryable message, not an exception',
        () async {
      final controller = controllerWith([])
        ..userBooksFailure = const NetworkException("You're offline");

      await controller.load();

      expect(controller.errorMessage, "You're offline");
      expect(controller.isLoading, isFalse);
    });
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
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
      await controller.load();

      final result = await controller.finishBook('Dune');

      expect(result.success, isFalse);
      expect(result.message, '"Dune" is already finished.');
    });
  });

  group('rateBook', () {
    test('rates a finished book and shows the star', () async {
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
      await controller.load();

      final result = await controller.rateBook('dune', 4.5);

      expect(result.success, isTrue);
      expect(result.message, '"Dune" — 4.5★');
      expect(controller.finished.single.rating, 4.5);
    });

    test('rounds a rating to the nearest half star before saving', () async {
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
      await controller.load();

      final result = await controller.rateBook('Dune', 4.3);

      expect(result.success, isTrue);
      expect(result.message, '"Dune" — 4.5★', reason: '4.3 is closer to 4.5 than 4.0');
      expect(controller.finished.single.rating, 4.5);
    });

    test('formats a rounded whole rating without a trailing .0', () async {
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
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
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
      await controller.load();

      final tooHigh = await controller.rateBook('Dune', 6);
      final zero = await controller.rateBook('Dune', 0);

      expect(tooHigh.success, isFalse);
      expect(zero.success, isFalse);
      expect(userBooks.rates, 0);
    });

    test('rolls back when the write fails', () async {
      final controller = controllerWith([_entry(_dune, page: 400, finished: true)]);
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

    test('leaves the finished book untouched by an unrelated delete',
        () async {
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
