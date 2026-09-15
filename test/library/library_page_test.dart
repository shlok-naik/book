import 'dart:async';

import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_series_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_series.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/pages/book_detail_page.dart';
import 'package:book/features/library/presentation/pages/library_page.dart';
import 'package:book/features/library/presentation/pages/series_page.dart';
import 'package:book/features/library/presentation/series_tile_style_controller.dart';
import 'package:book/features/library/presentation/widgets/book_cover.dart';
import 'package:book/features/library/presentation/widgets/series_cover.dart';
import 'package:book/features/logging/presentation/widgets/confirmation_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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
  LibraryException? failure;

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

  final savedOrders = <List<String>>[];
  int shelfChanges = 0;

  /// When set, shelf changes wait on it — lets a test act while a move is
  /// still being saved.
  Completer<void>? gate;

  @override
  Future<UserBook> changeShelf(UserBook updated) async {
    shelfChanges++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return updated.copyWith(clearShelfPosition: true);
  }

  final deleted = <String>[];

  @override
  Future<void> delete(String userBookId) async => deleted.add(userBookId);

  @override
  Future<void> saveShelfOrder(List<String> orderedIds) async {
    if (failure != null) throw failure!;
    savedOrders.add(orderedIds);
  }
}

/// The reader's series list, in memory — the "+" panel's series tab.
class _StubSeries extends BookSeriesRepository {
  final mine = <BookSeries>[];

  @override
  Future<List<BookSeries>> fetchMySeries() async => List.of(mine);

  @override
  Future<BookSeries> makeSeries(String name) async {
    final made = BookSeries(id: 'series-${mine.length}', name: name.trim());
    mine.add(made);
    return made;
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
  bool toBeRead = false,
  bool dnf = false,
  double? rating,
  String? shelfId,
  String? seriesId,
  double? seriesPosition,
}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
      shelfId: shelfId,
      id: 'progress-${book.id}',
      bookId: book.id,
      currentPage: page,
      status: finished
          ? ReadingStatus.finished
          : toBeRead
          ? ReadingStatus.toBeRead
          : dnf
          ? ReadingStatus.dnf
          : ReadingStatus.reading,
      rating: rating,
      seriesId: seriesId,
      seriesPosition: seriesPosition,
    ),
  );
}

void main() {
  LibraryController controllerFor(
    List<LibraryBook> rows, {
    LibraryException? failure,
    FakeCollectionsRepository? collections,
    _StubSeries? series,
  }) {
    return LibraryController(
      lookup: BookLookupService(
        cache: UnusedCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: StubUserBookRepository(rows, failure: failure),
      collections: collections ?? FakeCollectionsRepository(),
      series: series ?? _StubSeries(),
    );
  }

  /// Pumps the page. The to-read shelf starts closed (see the test
  /// "to read starts closed"); [openToRead] opens it first, since most tests
  /// here are about what happens on or between open shelves.
  Future<void> pumpPage(
    WidgetTester tester,
    LibraryController controller, {
    bool openToRead = true,
  }) async {
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
    if (openToRead) {
      // Everything but reading starts closed; most tests are about what's
      // inside "to read" and the series row, so open both when present.
      for (final label in ['Show to read books', 'Show series']) {
        final toggle = find.bySemanticsLabel(label);
        if (toggle.evaluate().isNotEmpty) {
          await tester.tap(toggle);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
        }
      }
    }
  }

  Finder emptyShelf(ReadingStatus status) =>
      find.byKey(ValueKey('empty-shelf-${status.name}'));

  /// Finished and did not finish start collapsed to just their heading —
  /// expands one so a test can see what's under it.
  Future<void> expandShelf(WidgetTester tester, String spoken) async {
    await tester.tap(
      find.bySemanticsLabel('Show ${spoken.toLowerCase()} books'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// No instructional copy anywhere on the shelf — drop targets and empty
  /// shelves are signalled by outline and highlight alone.
  void expectNoPromptCopy() {
    expect(find.textContaining('drop here'), findsNothing);
    expect(find.textContaining('Nothing here'), findsNothing);
    expect(find.textContaining('put it last'), findsNothing);
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
  });

  testWidgets('always shows every shelf, empty ones as a bare heading and '
      'an empty area', (tester) async {
    await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));

    for (final heading in [
      'reading',
      'to read',
      'finished',
      'did not finish',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(emptyShelf(ReadingStatus.reading), findsNothing);
    expect(emptyShelf(ReadingStatus.toBeRead), findsOneWidget);
    // Finished and did not finish start collapsed; expand them to see
    // their own empty area underneath.
    await expandShelf(tester, 'finished');
    await expandShelf(tester, 'did not finish');
    expect(emptyShelf(ReadingStatus.finished), findsOneWidget);
    expect(emptyShelf(ReadingStatus.dnf), findsOneWidget);
    expectNoPromptCopy();
  });

  testWidgets(
    'the collapse button hides a shelf\'s books without hiding its heading',
    (tester) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(_dune, page: 120),
          _entry(_noCover, toBeRead: true),
        ]),
      );

      expect(find.text('Dune'), findsWidgets);
      expect(find.bySemanticsLabel('Hide reading books'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Hide reading books'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The heading (and its count) stays; the cover and its own text go.
      expect(find.text('reading'), findsOneWidget);
      expect(find.text('Dune'), findsNothing);
      expect(find.bySemanticsLabel('Show reading books'), findsOneWidget);
      // A shelf never collapsed is untouched.
      expect(find.text('Pale Fire'), findsWidgets);

      // Tapping again brings it back.
      await tester.tap(find.bySemanticsLabel('Show reading books'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Dune'), findsWidgets);
    },
  );

  testWidgets('only reading starts open — custom shelves and the series row '
      'start closed too', (tester) async {
    await pumpPage(
      tester,
      controllerFor(
        [
          _entry(_dune, page: 120),
          _entry(_noCover, toBeRead: true, shelfId: 'shelf-summer'),
        ],
        collections: FakeCollectionsRepository(
          shelves: const [Shelf(id: 'shelf-summer', name: 'summer reads')],
        ),
      ),
      openToRead: false,
    );

    expect(find.bySemanticsLabel('Hide reading books'), findsOneWidget);
    for (final closed in [
      'Show to read books',
      'Show summer reads books',
      'Show finished books',
      'Show did not finish books',
    ]) {
      expect(find.bySemanticsLabel(closed), findsOneWidget, reason: closed);
    }
    // The book on the custom shelf is hidden until that shelf is opened.
    expect(find.text('Pale Fire'), findsNothing);
    await expandShelf(tester, 'summer reads');
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('to read starts closed, like finished and did not finish', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_noCover, toBeRead: true)]),
      openToRead: false,
    );

    expect(find.text('to read'), findsOneWidget);
    expect(find.bySemanticsLabel('Show to read books'), findsOneWidget);
    expect(find.text('Pale Fire'), findsNothing);

    await expandShelf(tester, 'to read');
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('an entirely empty library still shows all four shelves', (
    tester,
  ) async {
    await pumpPage(tester, controllerFor([]));

    await expandShelf(tester, 'finished');
    await expandShelf(tester, 'did not finish');
    for (final status in ReadingStatus.values) {
      expect(emptyShelf(status), findsOneWidget, reason: status.name);
    }
    expect(find.text('reading'), findsOneWidget);
    expect(find.text('did not finish'), findsOneWidget);
    expectNoPromptCopy();
  });

  testWidgets('headings are announced as headings, with a book count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 120), _entry(_noCover, page: 3)]),
    );

    final reading = tester.getSemantics(
      find.bySemanticsLabel('Reading, 2 books'),
    );
    expect(reading.getSemanticsData().flagsCollection.isHeader, isTrue);
    expect(find.bySemanticsLabel('To read, 0 books'), findsOneWidget);
    expect(find.bySemanticsLabel('To read shelf is empty'), findsOneWidget);
    semantics.dispose();
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
    await expandShelf(tester, 'finished');

    // The section heading and the finished book's own progress label.
    expect(find.text('finished'), findsNWidgets(2));
    expect(emptyShelf(ReadingStatus.finished), findsNothing);
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('separates to-be-read books into their own section', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, toBeRead: true),
      ]),
    );

    expect(emptyShelf(ReadingStatus.toBeRead), findsNothing);
    // Not started, and not lumped into the "reading" section above.
    expect(find.text('0/300 · 0%'), findsOneWidget);
  });

  testWidgets('separates did-not-finish books into their own section', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 120), _entry(_noCover, dnf: true)]),
    );
    await expandShelf(tester, 'did not finish');

    expect(emptyShelf(ReadingStatus.dnf), findsNothing);
    expect(emptyShelf(ReadingStatus.toBeRead), findsOneWidget);
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('a book that reaches its last page moves sections live', (
    tester,
  ) async {
    final controller = controllerFor([_entry(_dune, page: 120)]);
    await pumpPage(tester, controller);
    await expandShelf(tester, 'finished');
    expect(emptyShelf(ReadingStatus.finished), findsOneWidget);

    // No re-navigation, no manual refresh — just the same command the
    // log page dispatches.
    await controller.updateProgress('Dune', 400);
    await tester.pump();

    // "reading" is now an empty shelf, still on screen.
    expect(find.text('reading'), findsOneWidget);
    expect(emptyShelf(ReadingStatus.reading), findsOneWidget);
    expect(emptyShelf(ReadingStatus.finished), findsNothing);
    expect(find.text('finished'), findsNWidgets(2));
  });

  testWidgets('shows a star rating on a rated finished book', (tester) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 400, finished: true, rating: 3.5)]),
    );
    await expandShelf(tester, 'finished');

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

  testWidgets('a rating kept from a finished book is hidden once it moves', (
    tester,
  ) async {
    await pumpPage(
      tester,
      controllerFor([_entry(_dune, page: 0, toBeRead: true, rating: 4)]),
    );
    expect(find.byIcon(Icons.star), findsNothing);
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
    // An error replaces the shelves rather than showing four empty ones
    // that would read as "you have no books".
    expect(emptyShelf(ReadingStatus.reading), findsNothing);
  });

  testWidgets('tapping a book opens its detail page', (tester) async {
    await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));

    await tester.tap(find.text('120/400 · 30%'));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailPage), findsOneWidget);
  });

  group('drag and drop', () {
    /// Holds a finger on [from] past the long-press delay, then moves it in
    /// steps to wherever [to] resolves after the drag has started.
    Future<void> dragBook(
      WidgetTester tester,
      Finder from,
      Finder Function() to, {
      Offset nudge = Offset.zero,
    }) async {
      // Captured before the drag starts: once a book is held, its label
      // exists twice (the tile and the feedback following the finger).
      final start = tester.getCenter(from);
      final gesture = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 5));
      await tester.pump();
      final target = tester.getCenter(to().first) + nudge;
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(start, target, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('picking up a book adds no prompts and moves nothing around', (
      tester,
    ) async {
      await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));
      final zoneBefore = tester.getRect(emptyShelf(ReadingStatus.toBeRead));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('120/400 · 30%')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();

      expectNoPromptCopy();
      // Every empty shelf was already on screen, so holding a book doesn't
      // reflow the page under the reader's finger.
      expect(tester.getRect(emptyShelf(ReadingStatus.toBeRead)), zoneBefore);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('dropping on an empty shelf moves the book there and applies '
        'its side effects', (tester) async {
      final controller = controllerFor([_entry(_dune, page: 120)]);
      await pumpPage(tester, controller);

      await dragBook(
        tester,
        find.text('120/400 · 30%'),
        () => emptyShelf(ReadingStatus.toBeRead),
      );

      expect(controller.toBeRead.single.book.title, 'Dune');
      expect(controller.toBeRead.single.currentPage, 0);
      expect(find.text('Moved "Dune" to read'), findsOneWidget);
      expect(find.text('0/400 · 0%'), findsOneWidget);
      expect(emptyShelf(ReadingStatus.reading), findsOneWidget);
    });

    testWidgets('dropping on a heading puts the book first on that shelf', (
      tester,
    ) async {
      final controller = controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, page: 300, finished: true),
      ]);
      await pumpPage(tester, controller);

      await dragBook(
        tester,
        find.text('120/400 · 30%'),
        () => find.text('finished').first,
      );

      expect(controller.finished.map((e) => e.book.title), [
        'Dune',
        'Pale Fire',
      ]);
      expect(controller.finished.first.currentPage, 400);
    });

    testWidgets('dropping onto the right half of a tile lands after it', (
      tester,
    ) async {
      final controller = controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, page: 10),
      ]);
      await pumpPage(tester, controller);

      final paleFire = find.text('10/300 · 3%');
      await dragBook(
        tester,
        find.text('120/400 · 30%'),
        () => paleFire,
        nudge: Offset(tester.getSize(paleFire).width / 2 + 20, 0),
      );

      expect(controller.inProgress.map((e) => e.book.title), [
        'Pale Fire',
        'Dune',
      ]);
    });

    testWidgets('a failed move rolls back and says why', (tester) async {
      final repo = StubUserBookRepository([_entry(_dune, page: 120)]);
      final controller = LibraryController(
        lookup: BookLookupService(
          cache: UnusedCache(),
          googleBooks: GoogleBooksApiClient(
            client: MockClient((_) async => http.Response('{}', 200)),
          ),
        ),
        userBooks: repo,
      );
      await pumpPage(tester, controller);
      await expandShelf(tester, 'finished');
      repo.failure = const NetworkException("You're offline");

      await dragBook(
        tester,
        find.text('120/400 · 30%'),
        () => emptyShelf(ReadingStatus.finished),
      );

      expect(controller.inProgress.single.currentPage, 120);
      expect(find.text("You're offline"), findsOneWidget);
    });

    testWidgets('screen readers get the same moves as actions', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = controllerFor([_entry(_dune, page: 120)]);
      await pumpPage(tester, controller);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Dune by Frank Herbert')),
      );
      final actions = node.getSemanticsData().customSemanticsActionIds!.map(
        (id) => CustomSemanticsAction.getAction(id)!.label,
      );
      expect(
        actions,
        containsAll([
          'Move to to read',
          'Move to finished',
          'Move to did not finish',
        ]),
      );
      expect(actions, isNot(contains('Move to reading')));
      semantics.dispose();
    });
  });

  group('keyboard', () {
    /// Focuses the tile showing [label] the way Tab would.
    Future<void> focusTile(WidgetTester tester, String label) async {
      Focus.of(tester.element(find.text(label))).requestFocus();
      await tester.pump();
    }

    Future<void> altPress(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Enter opens the focused book', (tester) async {
      await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));
      await focusTile(tester, '120/400 · 30%');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(BookDetailPage), findsOneWidget);
    });

    testWidgets('Alt+Down moves the focused book to the next shelf', (
      tester,
    ) async {
      final controller = controllerFor([_entry(_dune, page: 120)]);
      await pumpPage(tester, controller);
      await focusTile(tester, '120/400 · 30%');

      await altPress(tester, LogicalKeyboardKey.arrowDown);

      expect(controller.toBeRead.single.book.title, 'Dune');
      expect(controller.toBeRead.single.currentPage, 0);
    });

    testWidgets('Alt+Right moves the focused book later on its shelf', (
      tester,
    ) async {
      final controller = controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, page: 10),
      ]);
      await pumpPage(tester, controller);
      await focusTile(tester, '120/400 · 30%');

      await altPress(tester, LogicalKeyboardKey.arrowRight);

      expect(controller.inProgress.map((e) => e.book.title), [
        'Pale Fire',
        'Dune',
      ]);
    });

    testWidgets('Alt+Up on the first shelf does nothing', (tester) async {
      final controller = controllerFor([_entry(_dune, page: 120)]);
      await pumpPage(tester, controller);
      await focusTile(tester, '120/400 · 30%');

      await altPress(tester, LogicalKeyboardKey.arrowUp);

      expect(controller.inProgress.single.currentPage, 120);
      expect(find.byType(ConfirmationPill), findsNothing);
    });

    testWidgets('a second move is ignored while the first is still saving', (
      tester,
    ) async {
      final repo = StubUserBookRepository([_entry(_dune, page: 120)])
        ..gate = Completer<void>();
      final controller = LibraryController(
        lookup: BookLookupService(
          cache: UnusedCache(),
          googleBooks: GoogleBooksApiClient(
            client: MockClient((_) async => http.Response('{}', 200)),
          ),
        ),
        userBooks: repo,
      );
      await pumpPage(tester, controller);
      await focusTile(tester, '120/400 · 30%');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await focusTile(tester, '0/400 · 0%');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      expect(repo.shelfChanges, 1);
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.toBeRead.single.book.title, 'Dune');
    });
  });

  group('search', () {
    Future<void> openSearch(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Search library'));
      await tester.pump();
    }

    testWidgets('filters every shelf to matching books and hides empty '
        'shelves', (tester) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(_dune, page: 120),
          _entry(_noCover, finished: true),
        ]),
      );
      await openSearch(tester);

      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        'nabokov',
      );
      await tester.pump();

      expect(find.text('Pale Fire'), findsWidgets);
      expect(find.text('Dune'), findsNothing);
      expect(find.text('reading'), findsNothing);
      expect(find.text('did not finish'), findsNothing);
      expect(emptyShelf(ReadingStatus.toBeRead), findsNothing);
    });

    testWidgets('says so when nothing matches, and closing restores the '
        'shelf', (tester) async {
      await pumpPage(tester, controllerFor([_entry(_dune, page: 120)]));
      await openSearch(tester);

      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        'tolkien',
      );
      await tester.pump();
      expect(find.text('no books match "tolkien".'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Close search'));
      await tester.pump();
      expect(find.text('Dune'), findsWidgets);
      expect(find.text('did not finish'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-search')), findsNothing);
    });
  });

  group('series', () {
    const messiah = Book(
      id: 'book-5',
      googleBooksId: 'gb-messiah',
      title: 'Dune Messiah',
      author: 'Frank Herbert',
      pageCount: 250,
    );
    const dune = Book(
      id: 'book-1',
      googleBooksId: 'gb-dune',
      title: 'Dune',
      author: 'Frank Herbert',
      pageCount: 400,
    );
    final duneSeries = _StubSeries()
      ..mine.add(const BookSeries(id: 'series-dune', name: 'Dune'));

    testWidgets('books in a series show as one group, in a row under to read '
        'that starts closed', (tester) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(
            messiah,
            toBeRead: true,
            seriesId: 'series-dune',
            seriesPosition: 2,
          ),
          _entry(
            dune,
            finished: true,
            seriesId: 'series-dune',
            seriesPosition: 1,
          ),
          _entry(_noCover),
        ], series: duneSeries),
        openToRead: false,
      );

      expect(find.text('series'), findsOneWidget);
      // Closed until opened.
      expect(find.text('2 books · 1 finished'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Show series'));
      await tester.pumpAndSettle();
      expect(find.text('2 books · 1 finished'), findsOneWidget);

      // Under "to read", above "finished".
      final seriesY = tester.getTopLeft(find.text('series')).dy;
      final toReadY = tester.getTopLeft(find.text('to read')).dy;
      final finishedY = tester.getTopLeft(find.text('finished').first).dy;
      expect(seriesY, greaterThan(toReadY));
      expect(seriesY, lessThan(finishedY));
    });

    testWidgets('no series row when nothing is in a series', (tester) async {
      await pumpPage(tester, controllerFor([_entry(_noCover)]));
      expect(find.text('series'), findsNothing);
    });

    testWidgets(
      'a series entirely on one shelf collapses to one grouped tile there',
      (tester) async {
        await pumpPage(
          tester,
          controllerFor([
            _entry(
              messiah,
              toBeRead: true,
              seriesId: 'series-dune',
              seriesPosition: 2,
            ),
            _entry(
              dune,
              toBeRead: true,
              seriesId: 'series-dune',
              seriesPosition: 1,
            ),
          ], series: duneSeries),
        );

        // Once for the horizontal row above the shelves, once for the
        // grouped tile inside "to read" — never a separate tile per book.
        expect(
          find.byKey(const ValueKey('series-series-dune')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('shelf-series-series-dune')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('progress-book-5')), findsNothing);
        expect(find.byKey(const ValueKey('progress-book-1')), findsNothing);
      },
    );

    testWidgets(
      'double-tapping a grouped series spreads it into its books, and '
      'double-tapping one of those folds it back',
      (tester) async {
        await pumpPage(
          tester,
          controllerFor([
            _entry(
              messiah,
              toBeRead: true,
              seriesId: 'series-dune',
              seriesPosition: 2,
            ),
            _entry(
              dune,
              toBeRead: true,
              seriesId: 'series-dune',
              seriesPosition: 1,
            ),
          ], series: duneSeries),
        );
        final grouped = find.byKey(const ValueKey('shelf-series-series-dune'));
        expect(grouped, findsOneWidget);

        await tester.tap(grouped);
        await tester.pump(kDoubleTapMinTime);
        await tester.tap(grouped);
        await tester.pumpAndSettle();

        expect(grouped, findsNothing);
        final book = find.byKey(const ValueKey('progress-book-1'));
        expect(book, findsOneWidget);

        await tester.tap(book);
        await tester.pump(kDoubleTapMinTime);
        await tester.tap(book);
        await tester.pumpAndSettle();

        expect(grouped, findsOneWidget);
        expect(book, findsNothing);
      },
    );

    testWidgets(
      'the series tiles setting swaps only the row between fan and patchwork',
      (tester) async {
        addTearDown(() => SeriesTileStyleController.patchwork.value = false);
        await pumpPage(
          tester,
          controllerFor([
            _entry(dune, toBeRead: true, seriesId: 'series-dune'),
            _entry(messiah, toBeRead: true, seriesId: 'series-dune'),
          ], series: duneSeries),
        );
        final row = find.byKey(const ValueKey('series-series-dune'));
        final grouped = find.byKey(const ValueKey('shelf-series-series-dune'));
        Finder patchworkIn(Finder f) =>
            find.descendant(of: f, matching: find.byType(SeriesPatchworkCover));

        // The grouped tile on the shelf is always a patchwork; the row starts
        // on the original fan.
        expect(patchworkIn(grouped), findsOneWidget);
        expect(patchworkIn(row), findsNothing);
        expect(
          find.descendant(of: row, matching: find.byType(SeriesFanCover)),
          findsOneWidget,
        );

        SeriesTileStyleController.patchwork.value = true;
        await tester.pump();

        // The switch changes only the row.
        expect(patchworkIn(row), findsOneWidget);
        expect(patchworkIn(grouped), findsOneWidget);

        // A grouped tile's patchwork is one cover's size: the tile's full
        // width at the 2:3 book ratio, exactly like a book's own cover.
        final patch = tester.getSize(patchworkIn(grouped));
        expect(patch.width, closeTo(tester.getSize(grouped).width, 0.5));
        expect(
          patch.width / patch.height,
          closeTo(BookCover.aspectRatio, 0.01),
        );
      },
    );

    testWidgets('tapping a group opens the series page in series order', (
      tester,
    ) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(
            messiah,
            toBeRead: true,
            seriesId: 'series-dune',
            seriesPosition: 2,
          ),
          _entry(
            dune,
            finished: true,
            seriesId: 'series-dune',
            seriesPosition: 1,
          ),
        ], series: duneSeries),
      );

      await tester.tap(find.byKey(const ValueKey('series-series-dune')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byType(SeriesPage), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      final first = tester.getTopLeft(find.text('#1')).dy;
      final second = tester.getTopLeft(find.text('#2')).dy;
      expect(first, lessThan(second));
      expect(
        find.descendant(
          of: find.byType(SeriesPage),
          matching: find.text('to read'),
        ),
        findsOneWidget,
      );
    });
  });

  group('making shelves, tags and series from the "+" panel', () {
    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('library-make-collections')));
      await tester.pumpAndSettle();
    }

    testWidgets('the "+" sits beside search and opens a four-tab panel', (
      tester,
    ) async {
      await pumpPage(tester, controllerFor([]));

      expect(
        find.bySemanticsLabel('Make or remove shelves, tags, series and books'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Search library'), findsOneWidget);
      final plus = tester.getCenter(
        find.byKey(const ValueKey('library-make-collections')),
      );
      final search = tester.getCenter(find.byIcon(Icons.search));
      expect(plus.dy, search.dy, reason: 'same row');
      expect(plus.dx, lessThan(search.dx), reason: 'just before search');

      await openPanel(tester);

      expect(find.text('shelves'), findsOneWidget);
      expect(find.text('tags'), findsOneWidget);
      expect(find.text('series'), findsOneWidget);
      expect(find.text('books'), findsOneWidget);
    });

    testWidgets('making a shelf adds it to the panel and as a new empty '
        'section on the page', (tester) async {
      PlanController.isPro.value = true;
      addTearDown(() => PlanController.isPro.value = false);
      final collections = FakeCollectionsRepository();
      final controller = controllerFor([
        _entry(_dune, page: 120),
      ], collections: collections);
      await pumpPage(tester, controller);
      await openPanel(tester);

      await tester.enterText(
        find.byKey(const ValueKey('make-shelf-field')),
        'summer reads',
      );
      await tester.tap(find.byKey(const ValueKey('make-shelf-button')));
      await tester.pumpAndSettle();

      expect(find.text('Made shelf "summer reads"'), findsOneWidget);
      expect(collections.shelves.single.name, 'summer reads');

      // A duplicate is refused through the same rule `make shelf` uses.
      await tester.enterText(
        find.byKey(const ValueKey('make-shelf-field')),
        'Summer Reads',
      );
      await tester.tap(find.byKey(const ValueKey('make-shelf-button')));
      await tester.pumpAndSettle();
      expect(
        find.text('You already have a shelf "Summer Reads".'),
        findsOneWidget,
      );
      expect(collections.creates, 1);

      Navigator.of(tester.element(find.text('make & remove'))).pop();
      await tester.pumpAndSettle();

      // A new shelf starts closed, like every shelf but reading.
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Show summer reads books'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await expandShelf(tester, 'summer reads');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('empty-shelf-custom-shelf-1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('summer reads'), findsOneWidget);
    });

    testWidgets('a built-in shelf name is refused in the panel', (
      tester,
    ) async {
      PlanController.isPro.value = true;
      addTearDown(() => PlanController.isPro.value = false);
      await pumpPage(tester, controllerFor([]));
      await openPanel(tester);

      await tester.enterText(
        find.byKey(const ValueKey('make-shelf-field')),
        'finished',
      );
      await tester.tap(find.byKey(const ValueKey('make-shelf-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('"finished" is already one of your built-in shelves.'),
        findsOneWidget,
      );
    });

    testWidgets('the tags and series tabs make their own kind', (tester) async {
      final controller = controllerFor([]);
      await pumpPage(tester, controller);
      await openPanel(tester);

      await tester.tap(find.byKey(const ValueKey('collections-tab-tags')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('make-tag-field')),
        'sci-fi',
      );
      await tester.tap(find.byKey(const ValueKey('make-tag-button')));
      await tester.pumpAndSettle();
      expect(controller.tags.single.name, 'sci-fi');
      expect(controller.shelves, isEmpty);

      await tester.tap(find.byKey(const ValueKey('collections-tab-series')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('make-series-field')),
        'The Expanse',
      );
      await tester.tap(find.byKey(const ValueKey('make-series-button')));
      await tester.pumpAndSettle();
      expect(find.text('Made series "The Expanse"'), findsOneWidget);
      expect(controller.mySeries.single.name, 'The Expanse');
      expect(controller.tags, hasLength(1));
    });

    testWidgets('a made shelf can be removed from its chip, after confirming', (
      tester,
    ) async {
      final collections = FakeCollectionsRepository(
        shelves: const [Shelf(id: 'shelf-1', name: 'summer')],
      );
      final controller = controllerFor([
        _entry(_dune, page: 120, shelfId: 'shelf-1'),
      ], collections: collections);
      await pumpPage(tester, controller);
      await openPanel(tester);

      Future<void> tapChipRemove(WidgetTester tester) async {
        final close = find.descendant(
          of: find.byKey(const ValueKey('remove-shelf-shelf-1')),
          matching: find.byIcon(Icons.close),
        );
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        await tester.tap(close);
        await tester.pumpAndSettle();
      }

      await tapChipRemove(tester);
      expect(find.text('remove shelf "summer"?'), findsOneWidget);

      // Cancelling changes nothing.
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(collections.deletedShelves, isEmpty);

      await tapChipRemove(tester);
      await tester.tap(find.text('remove'));
      await tester.pumpAndSettle();

      expect(collections.deletedShelves, ['shelf-1']);
      expect(find.text('Removed shelf "summer"'), findsOneWidget);
      expect(controller.inProgress.single.shelfId, isNull);
    });

    testWidgets('the books tab removes a book from the library, after '
        'confirming', (tester) async {
      final controller = controllerFor([
        _entry(_dune, page: 120),
        _entry(_noCover, toBeRead: true),
      ]);
      await pumpPage(tester, controller);
      await openPanel(tester);

      await tester.tap(find.byKey(const ValueKey('collections-tab-books')));
      await tester.pumpAndSettle();

      final remove = find.byKey(
        ValueKey('remove-book-${_entry(_noCover, toBeRead: true).id}'),
      );
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('delete Pale Fire?'), findsOneWidget);
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      expect(controller.books.single.book.title, 'Dune');
      expect(find.text('Removed "Pale Fire"'), findsOneWidget);
    });

    testWidgets('on the free plan, tags and series fade once their cap is '
        'reached, the same way shelves always do', (tester) async {
      final controller = controllerFor([]);
      await pumpPage(tester, controller);
      await openPanel(tester);

      double fade(String kind) => tester
          .widget<Opacity>(find.byKey(ValueKey('make-$kind-fade')))
          .opacity;

      // No custom shelves at all on the free plan.
      expect(fade('shelf'), 0.4);

      await tester.tap(find.byKey(const ValueKey('collections-tab-series')));
      await tester.pumpAndSettle();
      expect(fade('series'), 1, reason: 'one series is still free');
      await tester.enterText(
        find.byKey(const ValueKey('make-series-field')),
        'The Expanse',
      );
      await tester.tap(find.byKey(const ValueKey('make-series-button')));
      await tester.pumpAndSettle();
      expect(fade('series'), 0.4);

      await tester.tap(find.byKey(const ValueKey('collections-tab-tags')));
      await tester.pumpAndSettle();
      for (final name in ['sci-fi', 'cosy']) {
        expect(fade('tag'), 1);
        await tester.enterText(
          find.byKey(const ValueKey('make-tag-field')),
          name,
        );
        await tester.tap(find.byKey(const ValueKey('make-tag-button')));
        await tester.pumpAndSettle();
      }
      expect(fade('tag'), 0.4);
    });

    testWidgets('a book on a custom shelf shows under that shelf, and screen '
        'readers can move books onto it', (tester) async {
      const summer = Shelf(id: 'shelf-summer', name: 'summer reads');
      await pumpPage(
        tester,
        controllerFor([
          _entry(_dune, page: 120, shelfId: summer.id),
          _entry(_noCover, page: 30),
        ], collections: FakeCollectionsRepository(shelves: [summer])),
      );

      expect(emptyShelf(ReadingStatus.reading), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shelf-heading-custom-shelf-summer')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('summer reads'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('^Pale Fire')),
      );
      final labels = node.getSemanticsData().customSemanticsActionIds!.map(
        (id) => CustomSemanticsAction.getAction(id)!.label,
      );
      expect(labels, contains('Move to summer reads'));
      semantics.dispose();
    });
  });

  // Regression: tiles had a fixed 86px under the cover, which a two-line
  // title plus a rating overflowed with real fonts or larger phone text.
  testWidgets('rated tiles with long titles fit their cells at 1.3x text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const long = Book(
      id: 'book-long',
      googleBooksId: 'gb-long',
      title: 'Atomic Habits: An Easy and Proven Way to Build Good Habits',
      author: 'James Clear',
      pageCount: 320,
    );
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows.add(details.exceptionAsString());
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    await pumpPage(
      tester,
      controllerFor([
        _entry(_dune, page: 120),
        _entry(long, finished: true, rating: 4.5),
        _entry(_noCover, finished: true, rating: 3),
      ]),
    );
    await expandShelf(tester, 'finished');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Atomic Habits'), findsWidgets);
    expect(overflows, isEmpty);
  });
}
