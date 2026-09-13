import 'dart:async';

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
import 'package:book/features/library/presentation/pages/book_detail_page.dart';
import 'package:book/features/library/presentation/pages/library_page.dart';
import 'package:book/features/library/presentation/pages/series_page.dart';
import 'package:book/features/logging/presentation/widgets/confirmation_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

  @override
  Future<void> saveShelfOrder(List<String> orderedIds) async {
    if (failure != null) throw failure!;
    savedOrders.add(orderedIds);
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
}) {
  return LibraryBook(
    book: book,
    progress: UserBook(
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

  Finder emptyShelf(ReadingStatus status) =>
      find.byKey(ValueKey('empty-shelf-${status.name}'));

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
          _entry(_noCover, page: 300, finished: true),
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

  testWidgets('an entirely empty library still shows all four shelves', (
    tester,
  ) async {
    await pumpPage(tester, controllerFor([]));

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

    expect(emptyShelf(ReadingStatus.dnf), findsNothing);
    expect(emptyShelf(ReadingStatus.toBeRead), findsOneWidget);
    expect(find.text('Pale Fire'), findsWidgets);
  });

  testWidgets('a book that reaches its last page moves sections live', (
    tester,
  ) async {
    final controller = controllerFor([_entry(_dune, page: 120)]);
    await pumpPage(tester, controller);
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
      seriesId: 'series-dune',
      seriesName: 'Dune',
      seriesPosition: 2,
    );
    const dune = Book(
      id: 'book-1',
      googleBooksId: 'gb-dune',
      title: 'Dune',
      author: 'Frank Herbert',
      pageCount: 400,
      seriesId: 'series-dune',
      seriesName: 'Dune',
      seriesPosition: 1,
    );

    testWidgets('books in a series show as one group above the shelves', (
      tester,
    ) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(messiah, toBeRead: true),
          _entry(dune, finished: true),
          _entry(_noCover),
        ]),
      );

      expect(find.text('series'), findsOneWidget);
      expect(find.text('2 books · 1 finished'), findsOneWidget);
      final seriesY = tester.getTopLeft(find.text('series')).dy;
      final readingY = tester.getTopLeft(find.text('reading')).dy;
      expect(seriesY, lessThan(readingY));
    });

    testWidgets('no series row when nothing is in a series', (tester) async {
      await pumpPage(tester, controllerFor([_entry(_noCover)]));
      expect(find.text('series'), findsNothing);
    });

    testWidgets('tapping a group opens the series page in series order', (
      tester,
    ) async {
      await pumpPage(
        tester,
        controllerFor([
          _entry(messiah, toBeRead: true),
          _entry(dune, finished: true),
        ]),
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
}
