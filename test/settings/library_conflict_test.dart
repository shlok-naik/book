import 'package:book/core/auth/session_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/settings/presentation/pages/email_sheet.dart';
import 'package:book/features/settings/presentation/pages/library_conflict_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSession extends SessionService {
  _FakeSession({
    required this.account,
    required this.device,
    this.keepFailure,
    this.emailInUse = false,
  });

  final LibrarySummary account;
  final LibrarySummary device;
  final SessionException? keepFailure;
  final bool emailInUse;

  final kept = <bool>[];
  final signInCodes = <String>[];

  @override
  bool get isAnonymous => true;

  @override
  String? get userId => 'device-user';

  @override
  Future<LibrarySummary> accountSummary(PendingAccount account) async =>
      this.account;

  @override
  Future<LibrarySummary> deviceSummary() async => device;

  @override
  Future<void> keepLibrary(
    PendingAccount account, {
    required bool keepDevice,
  }) async {
    if (keepFailure != null) throw keepFailure!;
    kept.add(keepDevice);
  }

  @override
  Future<void> linkEmail(String email) async {
    if (emailInUse) throw EmailInUseException(email);
  }

  @override
  Future<void> sendSignInCode(String email) async => signInCodes.add(email);

  @override
  Future<PendingAccount> verifySignInCode({
    required String email,
    required String code,
  }) async =>
      PendingAccount(userId: 'email-user', email: email, refreshToken: 'r');
}

LibrarySummary _summary(int books, {int memories = 0, String? device}) =>
    LibrarySummary(
      bookCount: books,
      memoryCount: memories,
      eventCount: books,
      createdAt: DateTime(2026, 3, 4),
      lastSeenAt: DateTime(2026, 9, 1),
      deviceName: device,
    );

void main() {
  final pending = PendingAccount(
    userId: 'email-user',
    email: 'reader@example.com',
    refreshToken: 'refresh',
  );

  Future<List<String>> pumpConflict(
    WidgetTester tester,
    _FakeSession session,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final switched = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LibraryConflictPage(
                  session: session,
                  account: pending,
                  deviceName: () async => 'Google Pixel 8',
                  onSwitched: (_, userId) async => switched.add(userId),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return switched;
  }

  testWidgets('shows both libraries with device, books and dates', (
    tester,
  ) async {
    final session = _FakeSession(
      account: _summary(42, device: 'iPhone 15'),
      device: _summary(7, memories: 2),
    );
    await pumpConflict(tester, session);

    expect(find.text('the library on your email'), findsOneWidget);
    expect(find.text('the library on this device'), findsOneWidget);
    expect(find.text('iPhone 15'), findsOneWidget);
    expect(find.text('Google Pixel 8'), findsOneWidget);
    expect(find.text('42 books'), findsOneWidget);
    expect(find.text('7 books'), findsOneWidget);
    expect(find.text('3.4.26'), findsNWidgets(2));
    expect(session.kept, isEmpty);
  });

  testWidgets('keeping this device asks first, names what is deleted, then '
      'switches', (tester) async {
    final session = _FakeSession(
      account: _summary(42, memories: 3),
      device: _summary(7),
    );
    final switched = await pumpConflict(tester, session);

    await tester.tap(find.byKey(const ValueKey('keep-device')));
    await tester.pump();
    await tester.tap(find.text('keep this library'));
    await tester.pumpAndSettle();

    expect(find.text('delete the other library?'), findsOneWidget);
    expect(
      find.textContaining('reader@example.com — 42 books and 3 memories'),
      findsOneWidget,
    );
    await tester.tap(find.text('delete it'));
    await tester.pumpAndSettle();

    expect(session.kept, [true]);
    expect(switched, ['email-user']);
    expect(find.byType(LibraryConflictPage), findsNothing);
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final session = _FakeSession(account: _summary(1), device: _summary(1));
    await pumpConflict(tester, session);

    await tester.tap(find.byKey(const ValueKey('keep-account')));
    await tester.pump();
    await tester.tap(find.text('keep this library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(session.kept, isEmpty);
    expect(find.byType(LibraryConflictPage), findsOneWidget);
  });

  testWidgets('an empty device library joins the account without asking', (
    tester,
  ) async {
    final session = _FakeSession(
      account: _summary(42),
      device: const LibrarySummary(bookCount: 0, memoryCount: 0, eventCount: 0),
    );
    final switched = await pumpConflict(tester, session);

    expect(session.kept, [false]);
    expect(switched, ['email-user']);
    expect(find.byType(LibraryConflictPage), findsNothing);
  });

  testWidgets('a failure stays on the page with the message', (tester) async {
    final session = _FakeSession(
      account: _summary(2),
      device: _summary(3),
      keepFailure: const SessionException('Could not reach the server.'),
    );
    await pumpConflict(tester, session);

    await tester.tap(find.byKey(const ValueKey('keep-account')));
    await tester.pump();
    await tester.tap(find.text('keep this library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete it'));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the server.'), findsOneWidget);
    expect(find.byType(LibraryConflictPage), findsOneWidget);
  });

  testWidgets('the email sheet turns a taken email into a sign-in', (
    tester,
  ) async {
    final session = _FakeSession(
      account: _summary(1),
      device: _summary(1),
      emailInUse: true,
    );
    EmailSheetResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showEmailSheet(context, session: session),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'reader@example.com');
    await tester.tap(find.text('send code'));
    await tester.pumpAndSettle();

    expect(session.signInCodes, ['reader@example.com']);
    expect(find.textContaining('already has a cactus library'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('verify'));
    await tester.pumpAndSettle();

    expect(result?.existingAccount?.userId, 'email-user');
  });

  test('library summary parses the RPC row', () {
    final summary = LibrarySummary.fromRow({
      'book_count': 12,
      'memory_count': '3',
      'event_count': 40,
      'created_at': '2026-01-02T10:00:00Z',
      'device_name': ' Pixel 8 ',
      'last_seen_at': null,
    });
    expect(summary.bookCount, 12);
    expect(summary.memoryCount, 3);
    expect(summary.deviceName, 'Pixel 8');
    expect(summary.lastSeenAt, isNull);
    expect(summary.isEmpty, isFalse);
  });
}
