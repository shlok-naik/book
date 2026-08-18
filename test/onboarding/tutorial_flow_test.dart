import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:book/features/onboarding/domain/onboarding_averages.dart';
import 'package:book/features/onboarding/domain/onboarding_profile_draft.dart';
import 'package:book/features/onboarding/presentation/pages/add_book_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/description_page.dart';
import 'package:book/features/onboarding/presentation/pages/finish_page.dart';
import 'package:book/features/onboarding/presentation/pages/founders_note_page.dart';
import 'package:book/features/onboarding/presentation/pages/have_we_met_page.dart';
import 'package:book/features/onboarding/presentation/pages/name_page.dart';
import 'package:book/features/onboarding/presentation/pages/one_more_thing_page.dart';
import 'package:book/features/onboarding/presentation/pages/paywall_page.dart';
import 'package:book/features/onboarding/presentation/pages/protect_account_page.dart';
import 'package:book/features/onboarding/presentation/pages/reading_goal_page.dart';
import 'package:book/features/onboarding/presentation/pages/sign_in_page.dart';
import 'package:book/features/onboarding/presentation/pages/theme_preference_page.dart';
import 'package:book/features/onboarding/presentation/widgets/onboarding_progress_dots.dart';
import 'package:book/features/onboarding/presentation/widgets/soft_pill_button.dart';
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

  int sendEmailConfirmationCalls = 0;
  OnboardingException? sendEmailConfirmationFailure;

  @override
  Future<void> sendEmailConfirmation(String email) async {
    sendEmailConfirmationCalls++;
    if (sendEmailConfirmationFailure != null) {
      throw sendEmailConfirmationFailure!;
    }
  }

  int verifyEmailCodeCalls = 0;
  OnboardingException? verifyEmailCodeFailure;

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    verifyEmailCodeCalls++;
    if (verifyEmailCodeFailure != null) throw verifyEmailCodeFailure!;
    signedIn = true;
  }
}

class FakeProfileRepository extends OnboardingProfileRepository {
  OnboardingProfileDraft? savedDraft;
  int saveProfileCalls = 0;
  OnboardingException? saveProfileFailure;

  @override
  Future<void> saveProfile(OnboardingProfileDraft draft) async {
    saveProfileCalls++;
    savedDraft = draft;
    if (saveProfileFailure != null) throw saveProfileFailure!;
  }

  OnboardingAverages averages = const OnboardingAverages();

  @override
  Future<OnboardingAverages> fetchAverages() async => averages;
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

/// HalfSheetScaffold's half-height card can need more room than the
/// default 800x600 flutter_test surface offers once a heading and a
/// field/button are in it.
Future<void> useDeviceSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

int _progressStep(WidgetTester tester) => tester
    .widget<OnboardingProgressDots>(find.byType(OnboardingProgressDots))
    .currentStep;

/// Every onboarding action lives on a [SoftPillButton] now (the shared
/// pill treatment), so tapping by label goes through this instead of
/// the old `FilledButton`/`OutlinedButton` finders.
Future<void> tapPill(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SoftPillButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Like [tapPill], but for a tap that enters or leaves [PaywallPage] —
/// its feature wall auto-scrolls forever (the same marquee ticker as
/// the tutorial page's command wall), so a settle-based pump would
/// never return while it's mounted. Fixed pumps stand in instead.
Future<void> tapWithoutSettling(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(SoftPillButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'walks tutorial -> theme -> reading goal -> have we met (no) -> name '
    '-> description -> protect account -> paywall -> one more thing -> '
    "founder's note -> finish -> app",
    (tester) async {
      await useDeviceSize(tester);
      final session = FakeSessionService();
      final profiles = FakeProfileRepository();
      await tester.pumpWidget(
        harness(AddBookTutorialPage(session: session, profiles: profiles)),
      );
      // Lets the command wall's post-frame width measurement (and the
      // setState it triggers) land before checking its content.
      await tester.pump();

      expect(find.text('start The Shining'), findsWidgets);
      expect(find.text('log books as you read them'), findsOneWidget);
      // The step indicator is deliberately absent on the tutorial page.
      expect(find.byType(OnboardingProgressDots), findsNothing);

      await tapPill(tester, 'continue');

      expect(find.byType(ThemePreferencePage), findsOneWidget);
      expect(find.text('pick a look'), findsOneWidget);
      expect(_progressStep(tester), 2);

      await tapPill(tester, 'continue');

      expect(find.byType(ReadingGoalPage), findsOneWidget);
      expect(
        find.text('how many books do you plan to read this year?'),
        findsOneWidget,
      );
      expect(_progressStep(tester), 3);

      await tester.enterText(find.byType(TextField), '24');
      await tapPill(tester, 'continue');

      expect(find.byType(HaveWeMetPage), findsOneWidget);
      expect(_progressStep(tester), 4);

      await tapPill(tester, 'no');

      expect(find.byType(NamePage), findsOneWidget);
      expect(_progressStep(tester), 4);

      await tester.enterText(find.byType(TextField), 'ada');
      await tapPill(tester, 'continue');

      expect(find.byType(DescriptionPage), findsOneWidget);
      expect(_progressStep(tester), 4);

      await tester.enterText(find.byType(TextField), 'reads on the subway');
      await tapPill(tester, 'continue');

      expect(find.byType(ProtectAccountPage), findsOneWidget);
      expect(_progressStep(tester), 4);

      await tester.enterText(find.byType(TextField), 'ada@example.com');
      await tapPill(tester, 'send code');

      expect(session.sendEmailConfirmationCalls, 1);

      await tester.enterText(find.byType(TextField), '123456');
      // This tap lands on PaywallPage, whose feature tiles auto-scroll
      // forever, so pumpAndSettle would never return.
      await tapWithoutSettling(tester, 'verify');

      expect(session.verifyEmailCodeCalls, 1);
      expect(profiles.saveProfileCalls, 1);
      expect(profiles.savedDraft?.readingGoal, 24);
      // Q2 (reading time) was removed, so this is never collected.
      expect(profiles.savedDraft?.readingMinutesPerDay, isNull);
      expect(profiles.savedDraft?.name, 'ada');
      expect(profiles.savedDraft?.description, 'reads on the subway');

      // The paywall skips HalfSheetScaffold, so it has no progress dots
      // to check.
      expect(find.byType(PaywallPage), findsOneWidget);

      // Tapped from inside PaywallPage, whose feature wall animates
      // forever, so no settling here either. The label is "join now"
      // rather than the trial CTA — that one only appears once the
      // free-trial toggle is switched on.
      await tapWithoutSettling(tester, 'join now');

      expect(find.byType(OneMoreThingPage), findsOneWidget);
      expect(_progressStep(tester), 5);

      await tapPill(tester, 'continue');

      expect(find.byType(FoundersNotePage), findsOneWidget);
      expect(_progressStep(tester), 5);

      await tapPill(tester, 'continue');

      expect(find.byType(FinishPage), findsOneWidget);
      expect(_progressStep(tester), 5);

      await tapPill(tester, "let's go");

      expect(find.byType(FinishPage), findsNothing);
      // Lands on RootShell's default page (the log page).
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('have we met (yes) goes straight to sign in, then paywall', (
    tester,
  ) async {
    await useDeviceSize(tester);
    final session = FakeSessionService();
    final profiles = FakeProfileRepository();
    await tester.pumpWidget(
      harness(
        HaveWeMetPage(
          session: session,
          profiles: profiles,
          draft: const OnboardingProfileDraft(readingGoal: 24),
        ),
      ),
    );

    await tapPill(tester, 'yes');

    expect(find.byType(SignInPage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tapPill(tester, 'send code');

    expect(session.sendEmailConfirmationCalls, 1);

    await tester.enterText(find.byType(TextField), '123456');
    await tapWithoutSettling(tester, 'verify');

    expect(session.verifyEmailCodeCalls, 1);
    // A returning reader's Q1 answer is still saved, updating just that
    // one column.
    expect(profiles.saveProfileCalls, 1);
    expect(profiles.savedDraft?.readingGoal, 24);
    expect(find.byType(PaywallPage), findsOneWidget);
  });

  testWidgets(
    'shows an error and stays put when sending the sign-in code fails',
    (tester) async {
      await useDeviceSize(tester);
      final session = FakeSessionService()
        ..sendEmailConfirmationFailure = const OnboardingException(
          "You're offline",
        );
      await tester.pumpWidget(
        harness(
          SignInPage(
            session: session,
            profiles: FakeProfileRepository(),
            draft: const OnboardingProfileDraft(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ada@example.com');
      await tester.tap(find.widgetWithText(SoftPillButton, 'send code'));
      await tester.pump();
      await tester.pump();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.byType(SignInPage), findsOneWidget);
    },
  );

  testWidgets(
    'shows an error and stays put when sending the confirmation email fails',
    (tester) async {
      await useDeviceSize(tester);
      final session = FakeSessionService()
        ..sendEmailConfirmationFailure = const OnboardingException(
          "You're offline",
        );
      await tester.pumpWidget(
        harness(
          ProtectAccountPage(
            session: session,
            profiles: FakeProfileRepository(),
            draft: const OnboardingProfileDraft(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ada@example.com');
      await tester.tap(find.widgetWithText(SoftPillButton, 'send code'));
      await tester.pump();
      await tester.pump();

      expect(find.text("You're offline"), findsOneWidget);
      expect(find.byType(ProtectAccountPage), findsOneWidget);
    },
  );

  testWidgets(
    'shows an error and stays put when the confirmation code is wrong',
    (tester) async {
      await useDeviceSize(tester);
      final session = FakeSessionService()
        ..verifyEmailCodeFailure = const OnboardingException(
          'Token has expired or is invalid',
        );
      await tester.pumpWidget(
        harness(
          ProtectAccountPage(
            session: session,
            profiles: FakeProfileRepository(),
            draft: const OnboardingProfileDraft(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ada@example.com');
      await tapPill(tester, 'send code');

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.widgetWithText(SoftPillButton, 'verify'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Token has expired or is invalid'), findsOneWidget);
      expect(find.byType(ProtectAccountPage), findsOneWidget);
    },
  );

  testWidgets(
    'still reaches the paywall even when saving the profile fails after '
    'verifying',
    (tester) async {
      await useDeviceSize(tester);
      final session = FakeSessionService();
      final profiles = FakeProfileRepository()
        ..saveProfileFailure = const OnboardingException(
          "We couldn't save that.",
        );
      await tester.pumpWidget(
        harness(
          ProtectAccountPage(
            session: session,
            profiles: profiles,
            draft: const OnboardingProfileDraft(name: 'ada'),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ada@example.com');
      await tapPill(tester, 'send code');

      await tester.enterText(find.byType(TextField), '123456');
      await tapWithoutSettling(tester, 'verify');

      expect(profiles.saveProfileCalls, 1);
      expect(find.byType(PaywallPage), findsOneWidget);
    },
  );

  testWidgets(
    'shows the fetched average reading goal on the reading goal page',
    (tester) async {
      await useDeviceSize(tester);
      final profiles = FakeProfileRepository()
        ..averages = const OnboardingAverages(
          readingGoal: 24,
          readingMinutesPerDay: 45,
        );
      await tester.pumpWidget(
        harness(
          ReadingGoalPage(session: FakeSessionService(), profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('the average reader here plans for 24 books this year.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'hides the average line on the reading goal page when there is no '
    'data yet',
    (tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        harness(
          ReadingGoalPage(
            session: FakeSessionService(),
            profiles: FakeProfileRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('the average reader'), findsNothing);
    },
  );
}
