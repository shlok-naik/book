import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/streaks/presentation/pages/year_in_books_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class _Purchases extends PurchasesService {
  _Purchases({required this.pro});

  final bool pro;

  @override
  Future<CustomerInfo> get customerInfo async {
    final entitlements = pro
        ? {
            Entitlements.cactusPro: const EntitlementInfo(
              Entitlements.cactusPro,
              true,
              true,
              '2024-01-01T00:00:00Z',
              '2024-01-01T00:00:00Z',
              'yearly',
              false,
            ),
          }
        : const <String, EntitlementInfo>{};
    return CustomerInfo(
      EntitlementInfos(entitlements, entitlements),
      const {},
      const [],
      const [],
      const [],
      '2024-01-01T00:00:00Z',
      'fake-user-id',
      const {},
      '2024-01-01T00:00:00Z',
    );
  }
}

class _NoCache extends BookCacheRepository {
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
}

class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<DateTime?> fetchImportedAt() async => null;
}

LibraryBook _finished(String title, DateTime at, {double? rating}) =>
    LibraryBook(
      book: Book(
        id: 'b-$title',
        googleBooksId: 'g-$title',
        title: title,
        author: 'Someone',
        pageCount: 1200,
      ),
      progress: UserBook(
        id: 'u-$title',
        bookId: 'b-$title',
        currentPage: 1200,
        status: ReadingStatus.finished,
        finishedAt: at,
        rating: rating,
      ),
    );

void main() {
  final now = DateTime.now();

  tearDown(PlanController.reset);

  Future<void> pump(
    WidgetTester tester, {
    required bool pro,
    List<LibraryBook> rows = const [],
    CardSharer? share,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PlanController.isPro.value = pro;

    final library = LibraryController(
      lookup: BookLookupService(
        cache: _NoCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
          authHeaders: () async => const {},
        ),
      ),
      userBooks: _Shelf(rows),
    );
    addTearDown(library.dispose);
    await library.load();

    await tester.pumpWidget(
      LibraryScope(
        controller: library,
        child: MaterialApp(
          theme: AppTheme.light,
          home: YearInBooksPage(
            purchases: _Purchases(pro: pro),
            share: share,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a free reader sees the card but unlocks before sharing', (
    tester,
  ) async {
    await pump(
      tester,
      pro: false,
      rows: [_finished('Dune', DateTime(now.year, 1, 2), rating: 5)],
    );

    expect(find.text('unlock with cactus pro'), findsOneWidget);
    expect(find.text('share'), findsNothing);
  });

  testWidgets('shows the year and shares it as a png', (tester) async {
    List<int>? shared;
    String? name;
    await pump(
      tester,
      pro: true,
      rows: [
        _finished('Dune', DateTime(now.year, 1, 2), rating: 5),
        _finished('Emma', DateTime(now.year - 1, 6, 1)),
      ],
      share: (png, fileName) async {
        shared = png;
        name = fileName;
      },
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('book finished · 1,200 pages'), findsOneWidget);
    expect(find.textContaining('Dune — Someone'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('year-card-share')));
      for (var i = 0; i < 20 && shared == null; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    expect(name, 'cactus-${now.year}.png');
    // The PNG signature.
    expect(shared?.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('an empty year has nothing to share yet', (tester) async {
    await pump(tester, pro: true);

    expect(find.text('finish a book to share your year'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('year-card-share')),
    );
    expect(button.onPressed, isNull);
  });
}
