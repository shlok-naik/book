import 'dart:async';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_details_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_details_service.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/pages/book_detail_page.dart';
import 'package:book/features/library/presentation/pages/editions_page.dart';
import 'package:book/features/library/presentation/widgets/book_cover.dart';
import 'package:book/features/library/presentation/widgets/info_section.dart';
import 'package:book/features/library/presentation/widgets/tag_selection_sheet.dart';
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
  pageCount: 400,
);

/// A shelf that accepts every write and answers with exactly what was
/// written — enough for the page to show the controller's real
/// optimistic-then-persisted flow.
class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
  }) async => UserBook(
    id: userBookId,
    bookId: _dune.id,
    currentPage: currentPage,
    status: finished ? ReadingStatus.finished : ReadingStatus.reading,
  );

  @override
  Future<UserBook> changeShelf(UserBook updated) async => updated;

  final savedDates = <(DateTime, DateTime?)>[];

  @override
  Future<UserBook> saveDates(
    String userBookId, {
    required DateTime startedAt,
    DateTime? finishedAt,
  }) async {
    savedDates.add((startedAt, finishedAt));
    final row = rows.first.progress;
    return UserBook(
      id: userBookId,
      bookId: _dune.id,
      currentPage: row.currentPage,
      status: row.status,
      startedAt: startedAt.toUtc(),
      finishedAt: finishedAt?.toUtc(),
    );
  }

  @override
  Future<UserBook> rate({
    required String userBookId,
    required double rating,
  }) async => UserBook(
    id: userBookId,
    bookId: _dune.id,
    currentPage: 400,
    status: ReadingStatus.finished,
    rating: rating,
  );

  LibraryException? ownedFailure;

  @override
  Future<UserBook> setOwnedEdition(
    String userBookId,
    String? editionId, {
    required int currentPage,
  }) async {
    if (ownedFailure != null) throw ownedFailure!;
    return UserBook(
      id: userBookId,
      bookId: _dune.id,
      currentPage: currentPage,
      status: rows.first.status,
      ownedEditionId: editionId,
    );
  }
}

class _Details extends BookDetailsService {
  _Details()
    : super(
        cache: BookDetailsRepository(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('unused', 500)),
        ),
      );

  LibraryException? editionsFailure;
  bool noEditions = false;
  Completer<void>? editionsGate;
  int editionLoads = 0;

  @override
  Future<Book> detailsFor(Book book) async => Book(
    id: book.id,
    googleBooksId: book.googleBooksId,
    title: book.title,
    author: book.author,
    pageCount: book.pageCount,
    description: 'A desert planet and the spice.',
    publisher: 'Ace Books',
    publishedDate: '2005-08-02',
    categories: const ['Fiction'],
    language: 'en',
    isbn13: '9780441013593',
    averageRating: 4.2,
    ratingsCount: 310,
    detailsFetchedAt: DateTime.utc(2026),
  );

  @override
  Future<List<BookEdition>> editionsFor(Book book) async {
    editionLoads++;
    if (editionsGate != null) await editionsGate!.future;
    if (editionsFailure != null) throw editionsFailure!;
    if (noEditions) return const [];
    return const [
      BookEdition(
        id: 'edition-ebook',
        googleBooksId: 'g-e',
        title: 'Dune',
        author: 'Frank Herbert',
        format: EditionFormat.ebook,
        publisher: 'Penguin',
        publishedDate: '2010',
        pageCount: 200,
        isbn13: '9780000000002',
        language: 'fr',
        coverUrl: 'https://example.test/penguin.jpg',
      ),
      BookEdition(
        id: 'edition-hardback',
        googleBooksId: 'g-p',
        title: 'Dune',
        author: 'Frank Herbert',
        format: EditionFormat.physical,
        publishedDate: '1965',
        isbn13: '9780441013593',
      ),
    ];
  }
}

class _Notes extends BookNotesRepository {
  final tags = <BookTag>[];
  final comments = <BookComment>[];

  @override
  Future<List<BookTag>> fetchTags(String userBookId) async => List.of(tags);

  @override
  Future<List<BookComment>> fetchComments(String userBookId) async =>
      List.of(comments);

  @override
  Future<BookTag> addTag(String userBookId, ReaderTag tag) async {
    final saved = BookTag(
      id: 'tag-${tags.length}',
      userBookId: userBookId,
      tag: tag.name,
      createdAt: DateTime(2026),
    );
    tags.add(saved);
    return saved;
  }

  @override
  Future<void> removeTag(String tagId) async =>
      tags.removeWhere((t) => t.id == tagId);

  @override
  Future<BookComment> addComment(String userBookId, String body) async {
    final saved = BookComment(
      id: 'comment-${comments.length}',
      userBookId: userBookId,
      body: body,
      createdAt: DateTime(2026, 9, 13),
    );
    comments.add(saved);
    return saved;
  }
}

class _Cache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => _dune;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => _dune;
  @override
  Future<Book> cache(GoogleBook volume) async => _dune;
}

class _Events extends ReadingEventRepository {
  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {}
}

LibraryBook _entry({
  int page = 120,
  ReadingStatus status = ReadingStatus.reading,
}) => LibraryBook(
  book: _dune,
  progress: UserBook(
    id: 'progress-1',
    bookId: _dune.id,
    currentPage: page,
    status: status,
  ),
);

void main() {
  late _Details details;
  late _Notes notes;
  late _Shelf shelf;
  late LibraryController library;

  Future<void> pumpDetail(
    WidgetTester tester, {
    LibraryBook? entry,
    String userBookId = 'progress-1',
    List<NavigatorObserver> observers = const [],
    LibraryException? editionsFailure,
    bool noEditions = false,
    Completer<void>? editionsGate,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    details = _Details()
      ..editionsFailure = editionsFailure
      ..noEditions = noEditions
      ..editionsGate = editionsGate;
    notes = _Notes();
    shelf = _Shelf([entry ?? _entry()]);
    library = LibraryController(
      lookup: BookLookupService(
        cache: _Cache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: shelf,
      events: _Events(),
      notes: notes,
      details: details,
      // The tag field only applies tags that were made first.
      collections: FakeCollectionsRepository(
        tags: const [ReaderTag(id: 'reader-tag-sci-fi', name: 'sci-fi')],
      ),
    );
    addTearDown(library.dispose);
    await library.load();

    await tester.pumpWidget(
      LibraryScope(
        controller: library,
        child: MaterialApp(
          theme: AppTheme.light,
          navigatorObservers: observers,
          home: BookDetailPage(userBookId: userBookId),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Centred, not merely peeking in at an edge where a tap can land on
    // the list's own clip instead of the control.
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
  }

  TextField fieldIn(WidgetTester tester, String semanticsLabel) =>
      tester.widget<TextField>(
        find.descendant(
          of: find.bySemanticsLabel(semanticsLabel),
          matching: find.byType(TextField),
        ),
      );

  testWidgets('puts the book, where the reader is with it, and its key facts '
      'first', (tester) async {
    await pumpDetail(tester);

    expect(find.text('Dune'), findsWidgets);
    expect(find.text('Frank Herbert'), findsWidgets);
    // Status line: shelf and how far.
    expect(find.text('reading · 30%'), findsOneWidget);
    // Facts strip, scannable, with Google's date made readable.
    expect(find.text('400'), findsOneWidget);
    expect(find.text('2 Aug 2005'), findsOneWidget);
    expect(find.text('Ace Books'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
  });

  testWidgets('no longer offers to move the book between shelves', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.bySemanticsLabel(RegExp('^Shelf:')), findsNothing);
    expect(find.text('to read'), findsNothing);
    expect(find.text('dnf'), findsNothing);
  });

  testWidgets('keeps every detail field, lower down in about', (tester) async {
    await pumpDetail(tester);

    await scrollTo(tester, find.text('A desert planet and the spice.'));
    await scrollTo(tester, find.text('9780441013593'));
    expect(find.text('Fiction'), findsOneWidget);
    expect(find.text('4.2 / 5 (310 ratings)'), findsOneWidget);
  });

  testWidgets('shows editions as a single row, summarising what is behind it', (
    tester,
  ) async {
    await pumpDetail(tester);

    final row = find.bySemanticsLabel(RegExp('^Editions'));
    expect(row, findsOneWidget);
    expect(find.bySemanticsLabel('Editions, 2'), findsOneWidget);
    expect(find.textContaining('yours:'), findsNothing);
    // No list of editions on this page any more.
    expect(find.text('Penguin'), findsNothing);
    expect(find.text('physical'), findsNothing);
  });

  testWidgets('page and percent stay in sync, and save writes the page', (
    tester,
  ) async {
    await pumpDetail(tester);

    final page = find.descendant(
      of: find.bySemanticsLabel('Current page'),
      matching: find.byType(TextField),
    );
    final percent = find.descendant(
      of: find.bySemanticsLabel('Percent complete'),
      matching: find.byType(TextField),
    );
    await scrollTo(tester, page);
    expect(fieldIn(tester, 'Current page').controller!.text, '120');

    await tester.enterText(page, '200');
    await tester.pump();
    expect(fieldIn(tester, 'Percent complete').controller!.text, '50');

    await tester.enterText(percent, '25');
    await tester.pump();
    expect(fieldIn(tester, 'Current page').controller!.text, '100');

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(library.findById('progress-1')!.currentPage, 100);
    expect(find.text('"Dune" — pg 100'), findsOneWidget);
  });

  testWidgets('an out-of-range page is explained and not saved', (
    tester,
  ) async {
    await pumpDetail(tester);
    final page = find.descendant(
      of: find.bySemanticsLabel('Current page'),
      matching: find.byType(TextField),
    );
    await scrollTo(tester, page);

    await tester.enterText(page, '999');
    await tester.pump();
    expect(find.text('"Dune" only has 400 pages.'), findsOneWidget);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(library.findById('progress-1')!.currentPage, 120);
  });

  group('dates', () {
    LibraryBook dated(ReadingStatus status) => LibraryBook(
      book: _dune,
      progress: UserBook(
        id: 'progress-1',
        bookId: _dune.id,
        currentPage: status == ReadingStatus.finished ? 400 : 120,
        status: status,
        startedAt: DateTime(2026, 1, 2),
        finishedAt: status == ReadingStatus.finished
            ? DateTime(2026, 1, 20)
            : null,
      ),
    );

    testWidgets('a reading book shows its start date, and no finish date', (
      tester,
    ) async {
      await pumpDetail(tester, entry: dated(ReadingStatus.reading));
      await scrollTo(tester, find.byKey(const ValueKey('book-started-date')));

      expect(find.text('1.2.26'), findsOneWidget);
      expect(find.byKey(const ValueKey('book-finished-date')), findsNothing);
    });

    testWidgets('a finished book shows both', (tester) async {
      await pumpDetail(tester, entry: dated(ReadingStatus.finished));
      await scrollTo(tester, find.byKey(const ValueKey('book-finished-date')));

      expect(find.text('1.2.26'), findsOneWidget);
      expect(find.text('1.20.26'), findsOneWidget);
    });

    testWidgets('a book queued to read has no dates row', (tester) async {
      await pumpDetail(tester, entry: dated(ReadingStatus.toBeRead));
      expect(find.byKey(const ValueKey('book-started-date')), findsNothing);
    });

    testWidgets('picking a new start date saves it', (tester) async {
      await pumpDetail(tester, entry: dated(ReadingStatus.finished));
      await scrollTo(tester, find.byKey(const ValueKey('book-started-date')));

      await tester.tap(find.byKey(const ValueKey('book-started-date')));
      await tester.pumpAndSettle();
      expect(find.text('started on'), findsWidgets);

      // January 2026 is open; the finish on the 20th bounds the choice.
      await tester.tap(find.text('5').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(shelf.savedDates.single, (
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 20),
      ));
      expect(find.text('1.5.26'), findsOneWidget);
    });

    // Regression: the finish picker used to be bounded by the start date, so
    // a book added straight onto "finished" could only be finished on the
    // day it was added until the start date was changed first.
    testWidgets('backdating a finish before the start moves the start with '
        'it', (tester) async {
      await pumpDetail(tester, entry: dated(ReadingStatus.finished));
      await scrollTo(tester, find.byKey(const ValueKey('book-finished-date')));

      await tester.tap(find.byKey(const ValueKey('book-finished-date')));
      await tester.pumpAndSettle();
      // Started on the 2nd; the 1st is before it and still pickable.
      await tester.tap(find.text('1').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(shelf.savedDates.single, (
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 1),
      ));
    });
  });

  group('rating', () {
    testWidgets('is locked until the book is finished', (tester) async {
      await pumpDetail(tester);
      await scrollTo(tester, find.text('finish this book to rate it.'));

      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pumpAndSettle();
      expect(library.findById('progress-1')!.rating, isNull);
    });

    testWidgets('a finished book can be rated by tapping a star', (
      tester,
    ) async {
      await pumpDetail(
        tester,
        entry: _entry(page: 400, status: ReadingStatus.finished),
      );
      expect(find.text('finished'), findsOneWidget);
      await scrollTo(tester, find.bySemanticsLabel('Your rating'));
      expect(find.text('finish this book to rate it.'), findsNothing);

      // Right half of the fourth star: a whole 4.
      final fourth = find.byIcon(Icons.star_border).at(3);
      await tester.tapAt(
        tester.getCenter(fourth) + Offset(tester.getSize(fourth).width / 4, 0),
      );
      await tester.pumpAndSettle();

      expect(library.findById('progress-1')!.rating, 4);
    });

    testWidgets('arrow keys adjust the rating by half a star', (tester) async {
      await pumpDetail(
        tester,
        entry: _entry(page: 400, status: ReadingStatus.finished),
      );
      await scrollTo(tester, find.bySemanticsLabel('Your rating'));
      Focus.of(
        tester.element(find.byIcon(Icons.star_border).first),
      ).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(library.findById('progress-1')!.rating, 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(library.findById('progress-1')!.rating, 4.5);
    });

    testWidgets('is one adjustable control to a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDetail(
        tester,
        entry: _entry(page: 400, status: ReadingStatus.finished),
      );
      await scrollTo(tester, find.bySemanticsLabel('Your rating'));

      final data = tester
          .getSemantics(find.bySemanticsLabel('Your rating'))
          .getSemanticsData();
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.value, 'Not rated');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      semantics.dispose();
    });
  });

  testWidgets('selects and deselects a tag from the reader\'s own list', (
    tester,
  ) async {
    await pumpDetail(tester);
    // A button below the fold isn't built (so has no semantics node)
    // until the list scrolls to it.
    final button = find.text('add tags');
    await scrollTo(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add tag sci-fi'));
    await tester.pumpAndSettle();
    expect(notes.tags.single.tag, 'sci-fi');

    Navigator.of(tester.element(find.byType(TagSelectionSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.text('sci-fi'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Remove tag sci-fi'));
    await tester.pumpAndSettle();
    expect(find.text('sci-fi'), findsNothing);
  });

  testWidgets('a DNF book says how far the reader got, asks why, and saves '
      'the reason as a comment', (tester) async {
    await pumpDetail(tester, entry: _entry(status: ReadingStatus.dnf));
    expect(find.text('did not finish · stopped at 30%'), findsOneWidget);

    final field = find.widgetWithText(TextField, "why didn't you finish it?");
    await scrollTo(tester, field);

    await tester.enterText(field, 'too slow in the middle');
    await tester.tap(find.text('post'));
    await tester.pumpAndSettle();

    expect(find.text('too slow in the middle'), findsOneWidget);
    expect(notes.comments.single.body, 'too slow in the middle');
  });

  testWidgets('a book no longer on the shelf says so', (tester) async {
    await pumpDetail(tester, userBookId: 'gone');
    expect(
      find.text("this book isn't on your shelf any more."),
      findsOneWidget,
    );
  });

  testWidgets('picking an edition changes the book page to that copy', (
    tester,
  ) async {
    await pumpDetail(tester);
    // The work: 400 pages, Ace Books, English, page 120 = 30%.
    expect(find.text('Ace Books'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Editions')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Ebook edition')));
    await tester.pumpAndSettle();
    expect(
      find.text('Saved your edition — now page 60 of 200'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    // The copy the reader owns: its publisher, length, language, cover.
    expect(find.text('Penguin'), findsOneWidget);
    expect(find.text('Ace Books'), findsNothing);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
    expect(find.text('2010'), findsOneWidget);
    expect(find.text('reading · 30%'), findsOneWidget);
    final cover = tester.widget<BookCover>(find.byType(BookCover).first);
    expect(cover.coverUrl, 'https://example.test/penguin.jpg');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.bySemanticsLabel('Current page'),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '60',
    );
  });

  group('editions page', () {
    Future<void> openEditions(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^Editions')));
      await tester.pumpAndSettle();
    }

    testWidgets('the row opens a gallery of covers with their publishers', (
      tester,
    ) async {
      await pumpDetail(tester);
      await openEditions(tester);

      expect(find.byType(EditionsPage), findsOneWidget);
      expect(find.text('editions'), findsOneWidget);
      expect(find.text('Penguin'), findsOneWidget);
      // No publisher on record: said plainly rather than left blank.
      expect(find.text('unknown publisher'), findsOneWidget);
      expect(find.text('ebook · 2010'), findsOneWidget);
      expect(find.text('physical · 1965'), findsOneWidget);
      // A cover per edition — placeholders here, since the fixtures have no
      // cover URL.
      expect(find.byType(BookCover), findsNWidgets(2));
      // Reuses what the detail page already loaded.
      expect(details.editionLoads, 1);
    });

    testWidgets('follows the app routing pattern with a named route', (
      tester,
    ) async {
      final observer = _RouteNames();
      await pumpDetail(tester, observers: [observer]);
      await openEditions(tester);

      expect(observer.names.last, 'book_editions');

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(EditionsPage), findsNothing);
      expect(find.byType(BookDetailPage), findsOneWidget);
    });

    testWidgets('tapping a cover marks it owned; tapping again clears it', (
      tester,
    ) async {
      await pumpDetail(tester);
      await openEditions(tester);
      final ebook = find.bySemanticsLabel(RegExp('^Ebook edition'));

      await tester.tap(ebook);
      await tester.pumpAndSettle();
      expect(
        library.findById('progress-1')!.progress.ownedEditionId,
        'edition-ebook',
      );
      expect(
        find.text('Saved your edition — now page 60 of 200'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(ebook);
      await tester.pumpAndSettle();
      expect(library.findById('progress-1')!.progress.ownedEditionId, isNull);
      expect(
        find.text('Cleared your edition — now page 120 of 400'),
        findsOneWidget,
      );
      expect(library.findById('progress-1')!.currentPage, 120);
    });

    testWidgets('the owned edition shows back on the book page', (
      tester,
    ) async {
      await pumpDetail(tester);
      await openEditions(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Ebook edition')));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(find.text('you own the ebook (2010)'), findsOneWidget);
      // Same row shape as before picking one: the count stays, and the
      // owned edition gets its own line.
      expect(
        find.bySemanticsLabel('Editions, 2, yours: ebook · Penguin · 2010'),
        findsOneWidget,
      );
      expect(find.text('yours: ebook · Penguin · 2010'), findsOneWidget);
    });

    testWidgets('a cover can be chosen from the keyboard', (tester) async {
      await pumpDetail(tester);
      await openEditions(tester);

      Focus.of(tester.element(find.text('Penguin'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        library.findById('progress-1')!.progress.ownedEditionId,
        'edition-ebook',
      );
    });

    testWidgets('a save that fails leaves the edition unowned and says why', (
      tester,
    ) async {
      await pumpDetail(tester);
      shelf.ownedFailure = const NetworkException("You're offline");
      await openEditions(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Ebook edition')));
      await tester.pumpAndSettle();

      expect(library.findById('progress-1')!.progress.ownedEditionId, isNull);
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('a failed fetch shows a retry that recovers', (tester) async {
      await pumpDetail(
        tester,
        editionsFailure: const NetworkException(
          'Google Books is having trouble right now. Try again shortly.',
        ),
      );
      expect(find.bySemanticsLabel('Editions, unavailable'), findsOneWidget);
      await openEditions(tester);

      expect(
        find.text(
          'Google Books is having trouble right now. Try again shortly.',
        ),
        findsOneWidget,
      );
      details.editionsFailure = null;
      await tester.tap(find.text('try again'));
      await tester.pumpAndSettle();

      expect(find.text('Penguin'), findsOneWidget);
    });

    testWidgets('no editions is said plainly', (tester) async {
      await pumpDetail(tester, noEditions: true);
      expect(find.bySemanticsLabel('Editions, none found'), findsOneWidget);
      await openEditions(tester);

      expect(
        find.textContaining('no ebook or physical editions'),
        findsOneWidget,
      );
    });

    testWidgets('shows a loading state while editions are still coming', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pumpDetail(tester, editionsGate: gate, settle: false);
      await tester.tap(find.bySemanticsLabel(RegExp('^Editions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('finding ebook and physical editions…'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Penguin'), findsOneWidget);
    });
  });

  test('formatPublishedDate reads the way a person writes a date', () {
    expect(formatPublishedDate('2005'), '2005');
    expect(formatPublishedDate('2005-08'), 'Aug 2005');
    expect(formatPublishedDate('2005-08-02'), '2 Aug 2005');
    expect(formatPublishedDate('2005-13'), '2005');
    expect(formatPublishedDate('c. 1965'), 'c. 1965');
  });
}

/// Records the name of every route pushed, the way the analytics observer
/// sees them.
class _RouteNames extends NavigatorObserver {
  final names = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    names.add(route.settings.name);
  }
}
