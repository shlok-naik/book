import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/onboarding/data/onboarding_profile_repository.dart';
import 'package:book/features/onboarding/data/session_service.dart';
import 'package:book/features/onboarding/presentation/pages/add_book_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _NoopCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
  @override
  Future<Book> cache(GoogleBook volume) async => throw UnimplementedError();
}

class _EmptyUserBookRepository extends UserBookRepository {
  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];
}

class FakeSessionService extends SessionService {
  bool signedIn = false;

  @override
  bool get isSignedIn => signedIn;
}

Widget harness(Widget home) {
  return LibraryScope(
    controller: LibraryController(
      lookup: BookLookupService(
        cache: _NoopCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: _EmptyUserBookRepository(),
    ),
    child: MaterialApp(theme: AppTheme.light, home: home),
  );
}

void main() {
  /// "Welcome to / cactus" holds centered for 2s, then a 600ms reveal
  /// (slide + description fade-in), then a further 900ms pause, then a
  /// 400ms fade-in for the Start button — pumped in matching stages
  /// since each phase's controller/timer is only created once the
  /// previous one's `Future` resolves.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2050));
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('shows the "cactus" wordmark', (tester) async {
    await tester.pumpWidget(
      harness(
        WelcomePage(
          session: FakeSessionService(),
          profiles: OnboardingProfileRepository(),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('cactus'), findsOneWidget);
  });

  testWidgets('shows the description once settled', (tester) async {
    await tester.pumpWidget(
      harness(
        WelcomePage(
          session: FakeSessionService(),
          profiles: OnboardingProfileRepository(),
        ),
      ),
    );
    await settle(tester);

    expect(
      find.textContaining('next favourite reading companion'),
      findsOneWidget,
    );
    expect(
      find.textContaining('clean and beautiful interface'),
      findsOneWidget,
    );
  });

  testWidgets('shows the start button once settled, and tapping it opens '
      'the first tutorial step', (tester) async {
    await tester.pumpWidget(
      harness(
        WelcomePage(
          session: FakeSessionService(),
          profiles: OnboardingProfileRepository(),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('start'), findsOneWidget);

    await tester.tap(find.text('start'));
    // Not pumpAndSettle: the tutorial page's command wall animates
    // forever (a marquee), so a settle-based pump would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AddBookTutorialPage), findsOneWidget);
  });
}
