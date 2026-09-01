import 'package:book/core/theme/app_theme.dart';
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
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/pages/library_page.dart';
import 'package:flutter/material.dart';
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

/// Deliberately cover-less — the placeholder path.
const _noCover = Book(
  id: 'book-2',
  googleBooksId: 'gb-pale',
  title: 'Pale Fire',
  author: 'Vladimir Nabokov',
  pageCount: 300,
);

class StubUserBookRepository extends UserBookRepository {
  StubUserBookRepository(this.rows, {this.failure});

  final List<LibraryBook> rows;
  final LibraryException? failure;

  @override
  Future<List<LibraryBook>> fetchLibrary() async {
    if (failure != null) throw failure!;
    return List.of(rows);
  }

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
  }) async {
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: currentPage,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
    );
  }
}

class UnusedCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
  @override
  Future<Book> cache(GoogleBook volume) async =>
      throw const RemoteDataException('not used in this test');
}

LibraryBook _entry(
  Book book, {
  int page = 0,
  bool finished = false,
  double? rating,
}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
      id: 'progress-${book.id}',
      bookId: book.id,
      currentPage: page,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
      rating: rating,
    ),
  );
}

void main() {
  LibraryController controllerFor(
    List<LibraryBook> rows, {
    LibraryException? failure,
  }) {
    return LibraryController(
      lookup: BookLookupService(
        cache: UnusedCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: StubUserBookRepository(rows, failure: failure),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    LibraryController controller,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LibraryScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light, home: const LibraryPage()),
      ),
    );
    // One extra pump for the post-frame load(), one for its result.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows in-progress books with their progress readout', (
    tester,
  ) async {
    await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));

    expect(find.text('reading'), findsOneWidget);
    // Twice: the tile caption, and the cover placeholder standing in
    // for the image (network images always fail under flutter_test).
    expect(find.text('Dune'), findsNWidgets(2));
    expect(find.text('120/400 · 30%'), findsOneWidget);
    expect(find.text('finished'), findsNothing);
  });

  testWidgets('separates finished books into their own section', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, page: 300, finished: true),
      ]),
    );

    expect(find.text('reading'), findsOneWidget);
    // The section label and the finished book's own progress label.
    expect(find.text('finished'), findsNWidgets(2));
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('a book that reaches its last page moves sections live', (
    tester,
  ) async {
    final controller = controllerFor([_entry(_dune, page: 120)]);
    await pumpPage(tester, controller);
    expect(find.text('finished'), findsNothing);

    // No re-navigation, no manual refresh — just the same command the
    // log page dispatches.
    await controller.updateProgress('Dune', 400);
    await tester.pump();

    expect(find.text('reading'), findsNothing);
    expect(find.text('finished'), findsNWidgets(2));
  });

  testWidgets('shows a star rating on a rated finished book', (tester) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 400, finished: true, rating: 3.5)]),
    );

    // 3 full stars, 1 half, 1 outline for a 3.5 rating.
    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.byIcon(Icons.star_half), findsOneWidget);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    // The number itself, alongside the icons — a half star reads
    // ambiguously at 12px on its own.
    expect(find.text('3.5'), findsOneWidget);
  });

  testWidgets('shows no stars on a finished book that was never rated', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 400, finished: true)]),
    );

    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_half), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('falls back to a placeholder when a book has no cover', (
    tester,
  ) async {
    await pumpPage(tester, controllerFor([_entry(_noCover, page: 10)]));

    // The placeholder renders the title/author itself, so the tile keeps
    // its shape instead of collapsing.
    expect(find.byType(Image), findsNothing);
    expect(find.text('Pale Fire'), findsNWidgets(2));
  });

  testWidgets('shows a friendly message and a retry when the load fails', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([], failure: const NetworkException("You're offline")),
    );

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('invites the first book when the shelf is empty', (tester) async {
    await pumpPage(tester, controllerFor([]));

    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });
}
