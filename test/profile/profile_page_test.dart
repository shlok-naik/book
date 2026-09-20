import 'dart:async';

import 'package:book/core/auth/session_service.dart';
import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/profile/domain/profile_identity.dart';
import 'package:book/features/profile/presentation/pages/profile_page.dart';
import 'package:book/features/profile/presentation/profile_identity_controller.dart';
import 'package:book/features/search/domain/reading_taste.dart';
import 'package:book/features/search/presentation/reading_tastes_controller.dart';
import 'package:book/features/settings/data/profile_repository.dart';
import 'package:book/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_goals.dart';

/// The profile screen — who the reader is: the membership card, their
/// name and `@username`, the email that backs the shelf up, their tastes,
/// and one row into the settings screen. Everything underneath (the store,
/// the session, the profile repository, the shelf) is faked.

class _EmptyCache extends BookCacheRepository {
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
}

class _EmptyShelf extends UserBookRepository {
  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];

  @override
  Future<DateTime?> fetchImportedAt() async => null;
}

LibraryController _libraryController() => LibraryController(
  lookup: BookLookupService(
    cache: _EmptyCache(),
    googleBooks: GoogleBooksApiClient(
      client: MockClient((_) async => http.Response('{}', 200)),
      authHeaders: () async => const {},
    ),
  ),
  userBooks: _EmptyShelf(),
);

class _FakePurchasesService extends PurchasesService {
  _FakePurchasesService({required this.info});

  final CustomerInfo info;

  int customerCenterCalls = 0;
  int restoreCalls = 0;

  @override
  Future<CustomerInfo> get customerInfo async => info;

  @override
  Future<void> presentCustomerCenter() async => customerCenterCalls++;

  @override
  Future<CustomerInfo> restore() async {
    restoreCalls++;
    return info;
  }
}

class _FakeSession extends SessionService {
  _FakeSession({this.anonymous = true, this.address});

  final bool anonymous;
  final String? address;

  @override
  bool get isSignedIn => true;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get email => address;

  @override
  String? get userId => 'fake-user-id';
}

/// Never touches Supabase — [joinedAt] is what `fetchJoinedAt` returns,
/// the same role `FakePurchasesService` plays for RevenueCat.
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({DateTime? joinedAt})
    : _future = Future.value(joinedAt);

  /// Never resolves — for the one test that needs to catch the card
  /// mid-load, before `fetchJoinedAt` has answered at all.
  _FakeProfileRepository.pending() : _future = Completer<DateTime?>().future;

  final Future<DateTime?> _future;

  @override
  Future<DateTime?> fetchJoinedAt(String userId) => _future;
}

CustomerInfo _customerInfo({required bool pro}) {
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

Future<void> pumpProfile(
  WidgetTester tester, {
  required PurchasesService purchases,
  required SessionService session,
  ProfileRepository? profileRepository,
  GoalController? goals,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    GoalScope(
      controller: goals ?? goalControllerFor(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: LibraryScope(
          controller: _libraryController(),
          child: ProfilePage(
            purchases: purchases,
            session: session,
            profileRepository: profileRepository ?? _FakeProfileRepository(),
          ),
        ),
      ),
    ),
  );
  // One frame to mount, one for the entitlement fetch to resolve.
  await tester.pump();
  await tester.pump();
}

/// Scrolls the settings list until [finder] is built and on screen — its
/// rows are built lazily, so one below the fold doesn't exist to
/// `ensureVisible` until the list has scrolled near it.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('profile', () {
    testWidgets('reading tastes open a picker that saves as you tap', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ReadingTastesController.reset);
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('none yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-reading-tastes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('taste-fantasy')));
      await tester.pumpAndSettle();

      expect(ReadingTastesController.tastes.value, [ReadingTaste.fantasy]);
    });

    testWidgets('holds the email and memory rows', (tester) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('profile'), findsOneWidget);
      expect(find.text('link your email'), findsOneWidget);
      expect(find.text('memory'), findsOneWidget);
    });

    testWidgets('the name is set here, and lands on the card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ProfileIdentityController.reset);
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('not set'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-display-name-field')),
        'Ada',
      );
      await tester.tap(find.byKey(const ValueKey('edit-profile-save')));
      await tester.pumpAndSettle();

      expect(
        ProfileIdentityController.identity.value,
        const ProfileIdentity(displayName: 'Ada'),
      );
      // On the card itself, over the join date.
      expect(find.text('Ada'), findsWidgets);
    });

    testWidgets('a name is required', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ProfileIdentityController.reset);
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await tester.tap(find.byKey(const ValueKey('profile-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-profile-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter your name.'), findsOneWidget);
      expect(ProfileIdentityController.identity.value.isEmpty, isTrue);
    });

    testWidgets('one row leads to the settings screen', (tester) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await scrollTo(tester, find.byKey(const ValueKey('profile-settings')));
      await tester.tap(find.byKey(const ValueKey('profile-settings')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
    });
  });

  group('membership card', () {
    testWidgets('an anonymous reader is offered a backup, not a sign-out', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('link your email'), findsOneWidget);
      // Signing out of an anonymous account would strand its shelf
      // behind a uid nobody can authenticate as again.
      expect(find.text('sign out'), findsNothing);
      expect(
        find.textContaining('Your shelf lives on this device only'),
        findsOneWidget,
      );
    });

    testWidgets('a linked reader sees their address on the card', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(anonymous: false, address: 'reader@example.com'),
      );

      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text('change email'), findsOneWidget);
      expect(find.text('link your email'), findsNothing);
      // Signing out is not offered anywhere: for an anonymous reader
      // there is no credential to sign back in with, so it destroys a
      // library rather than protecting one.
      expect(find.text('sign out'), findsNothing);
    });

    testWidgets('the profile row opens the email sheet in its "link" wording', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await tester.tap(find.text('link your email'));
      await tester.pumpAndSettle();

      expect(find.text('send code'), findsOneWidget);
      expect(
        find.textContaining('a way back to you on another device'),
        findsOneWidget,
      );
    });

    testWidgets('the change row opens the same sheet, reworded to change it', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(anonymous: false, address: 'reader@example.com'),
      );

      await tester.tap(find.text('change email'));
      await tester.pumpAndSettle();

      // Same two-step sheet, same call underneath — only the copy
      // knows the difference.
      expect(find.text('send code'), findsOneWidget);
      expect(
        find.textContaining('only the address it answers to changes'),
        findsOneWidget,
      );
    });

    testWidgets('shows no PRO badge for a free reader', (tester) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('shows the PRO badge for a paying reader', (tester) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: true)),
        session: _FakeSession(),
      );
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('shows when the account was created', (tester) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
        profileRepository: _FakeProfileRepository(
          // Noon UTC, not midnight — safely the same calendar day once
          // `_dateLabel` converts it to local, regardless of which
          // timezone this test happens to run in.
          joinedAt: DateTime.utc(2026, 3, 5, 12),
        ),
      );

      expect(find.text('member since'), findsOneWidget);
      expect(find.text('3.5.26'), findsOneWidget);
    });

    testWidgets(
      'shows a loading placeholder rather than growing once the date lands',
      (tester) async {
        await pumpProfile(
          tester,
          purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
          session: _FakeSession(),
          profileRepository: _FakeProfileRepository.pending(),
        );

        // "member since" is never conditional on the fetch — only the
        // value below it is — so the card's height is already settled
        // here, before `fetchJoinedAt` has even answered.
        expect(find.text('member since'), findsOneWidget);
        expect(find.text('···'), findsOneWidget);
      },
    );

    testWidgets('shows a dash when the join date could not be loaded', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
        profileRepository: _FakeProfileRepository(),
      );

      expect(find.text('member since'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });
}
