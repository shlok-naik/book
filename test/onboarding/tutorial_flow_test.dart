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
import 'package:book/features/onboarding/presentation/pages/have_we_met_page.dart';
import 'package:book/features/onboarding/presentation/pages/name_page.dart';
import 'package:book/features/onboarding/presentation/pages/protect_account_page.dart';
import 'package:book/features/onboarding/presentation/pages/reading_goal_page.dart';
import 'package:book/features/onboarding/presentation/pages/reading_time_page.dart';
import 'package:book/features/onboarding/presentation/pages/sign_in_page.dart';
import 'package:book/features/onboarding/presentation/widgets/onboarding_progress_dots.dart';
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
  Future<void> verifyEmailCode({required String email, required String code}) async {
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

int _progressStep(WidgetTester tester) =>
    tester.widget<OnboardingProgressDots>(find.byType(OnboardingProgressDots)).currentStep;

void main() {
  testWidgets(
      'walks tutorial -> Q1 -> Q2 -> have we met (no) -> name -> '
      'description -> protect account -> finish -> app', (tester) async {
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

    await tester.tap(find.widgetWithText(FilledButton, 'continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ReadingGoalPage), findsOneWidget);
    expect(find.text('how many books do you plan to read this year?'), findsOneWidget);
    expect(_progressStep(tester), 2);

    await tester.enterText(find.byType(TextField), '24');
    await tester.tap(find.widgetWithText(FilledButton, 'continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ReadingTimePage), findsOneWidget);
    expect(
      find.text('how much time do you spend reading every day?'),
      findsOneWidget,
    );
    expect(_progressStep(tester), 3);

    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.widgetWithText(FilledButton, 'continue'));
    await tester.pumpAndSettle();

    expect(find.byType(HaveWeMetPage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.tap(find.widgetWithText(OutlinedButton, 'no'));
    await tester.pumpAndSettle();

    expect(find.byType(NamePage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.enterText(find.byType(TextField), 'ada');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'continue'));
    await tester.tap(find.widgetWithText(FilledButton, 'continue'));
    await tester.pumpAndSettle();

    expect(find.byType(DescriptionPage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.enterText(find.byType(TextField), 'reads on the subway');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'continue'));
    await tester.tap(find.widgetWithText(FilledButton, 'continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ProtectAccountPage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pumpAndSettle();

    expect(session.sendEmailConfirmationCalls, 1);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'verify'));
    await tester.pumpAndSettle();

    expect(session.verifyEmailCodeCalls, 1);
    expect(profiles.saveProfileCalls, 1);
    expect(profiles.savedDraft?.readingGoal, 24);
    expect(profiles.savedDraft?.readingMinutesPerDay, 45);
    expect(profiles.savedDraft?.name, 'ada');
    expect(profiles.savedDraft?.description, 'reads on the subway');
    expect(find.byType(FinishPage), findsOneWidget);
    expect(_progressStep(tester), 5);

    await tester.tap(find.widgetWithText(FilledButton, "let's go"));
    await tester.pumpAndSettle();

    expect(find.byType(FinishPage), findsNothing);
    // Lands on RootShell's default page (the log page).
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('have we met (yes) goes straight to sign in, then finish',
      (tester) async {
    await useDeviceSize(tester);
    final session = FakeSessionService();
    final profiles = FakeProfileRepository();
    await tester.pumpWidget(
      harness(
        HaveWeMetPage(
          session: session,
          profiles: profiles,
          draft: const OnboardingProfileDraft(readingGoal: 24, readingMinutesPerDay: 45),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'yes'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInPage), findsOneWidget);
    expect(_progressStep(tester), 4);

    await tester.enterText(find.byType(TextField), 'ada@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pumpAndSettle();

    expect(session.sendEmailConfirmationCalls, 1);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'verify'));
    await tester.pumpAndSettle();

    expect(session.verifyEmailCodeCalls, 1);
    // A returning reader's Q1/Q2 answers are still saved, updating just
    // those two columns.
    expect(profiles.saveProfileCalls, 1);
    expect(profiles.savedDraft?.readingGoal, 24);
    expect(profiles.savedDraft?.readingMinutesPerDay, 45);
    expect(find.byType(FinishPage), findsOneWidget);
  });

  testWidgets(
      'shows an error and stays put when sending the sign-in code fails',
      (tester) async {
    await useDeviceSize(tester);
    final session = FakeSessionService()
      ..sendEmailConfirmationFailure = const OnboardingException("You're offline");
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
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pump();
    await tester.pump();

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.byType(SignInPage), findsOneWidget);
  });

  testWidgets(
      'shows an error and stays put when sending the confirmation email fails',
      (tester) async {
    await useDeviceSize(tester);
    final session = FakeSessionService()
      ..sendEmailConfirmationFailure = const OnboardingException("You're offline");
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
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pump();
    await tester.pump();

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.byType(ProtectAccountPage), findsOneWidget);
  });

  testWidgets(
      'shows an error and stays put when the confirmation code is wrong',
      (tester) async {
    await useDeviceSize(tester);
    final session = FakeSessionService()
      ..verifyEmailCodeFailure = const OnboardingException('Token has expired or is invalid');
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
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'verify'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Token has expired or is invalid'), findsOneWidget);
    expect(find.byType(ProtectAccountPage), findsOneWidget);
  });

  testWidgets(
      'still finishes even when saving the profile fails after verifying',
      (tester) async {
    await useDeviceSize(tester);
    final session = FakeSessionService();
    final profiles = FakeProfileRepository()
      ..saveProfileFailure = const OnboardingException("We couldn't save that.");
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
    await tester.tap(find.widgetWithText(FilledButton, 'send code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'verify'));
    await tester.pumpAndSettle();

    expect(profiles.saveProfileCalls, 1);
    expect(find.byType(FinishPage), findsOneWidget);
  });

  testWidgets('shows the fetched average reading goal on Q1',
      (tester) async {
    await useDeviceSize(tester);
    final profiles = FakeProfileRepository()
      ..averages = const OnboardingAverages(readingGoal: 24, readingMinutesPerDay: 45);
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
  });

  testWidgets('hides the average line on Q1 when there is no data yet',
      (tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      harness(
        ReadingGoalPage(session: FakeSessionService(), profiles: FakeProfileRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('the average reader'), findsNothing);
  });
}
