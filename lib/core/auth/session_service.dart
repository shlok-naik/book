import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';
import 'account_link.dart';

export 'account_link.dart';

/// A failure from any [SessionService] call, already written for a
/// human — the UI shows [message] verbatim. The original error is kept
/// in [cause] for logging only, never rendered.
class SessionException implements Exception {
  const SessionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'SessionException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Thin wrapper over `Supabase.instance.client.auth` — the app's only
/// account surface.
///
/// The app has no sign-up step. Every feature reads through RLS on
/// `auth.uid()`, so a reader needs a session before the first screen
/// renders, and [ensureSession] is what provides one: an anonymous
/// Supabase user, created silently on first launch and reused
/// thereafter. An anonymous session still carries the real
/// `authenticated` role, so no policy has to know the difference.
///
/// The trade-off is that an anonymous account is per-install — reinstall
/// the app and the shelf is gone. [linkEmail]/[verifyEmailCode] are the
/// way out: they attach an email identity to the *existing* user rather
/// than creating a second one, so the uid survives and RevenueCat and
/// Crashlytics identities stay valid without re-linking.
///
/// Every method translates Supabase/network failures into a
/// [SessionException] with a message safe to show directly, the same way
/// `BookCacheRepository`/`UserBookRepository` translate Postgrest
/// failures into `LibraryException`s.
class SessionService {
  /// The client is resolved lazily rather than captured in the
  /// constructor, so a `SessionService` can be built before (or without)
  /// `Supabase.initialize` — widget tests construct one without it.
  SessionService({SupabaseClient? client, this.secondaryClientFactory})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Test seam for the sign-in client; null in the app.
  final SupabaseClient Function()? secondaryClientFactory;

  /// The client [sendSignInCode] signs in with — separate from the app's
  /// own, in memory only and never refreshed, so signing in to an email
  /// account can't replace this device's session behind the reader's back.
  SupabaseClient _newSecondaryClient() =>
      secondaryClientFactory?.call() ??
      SupabaseClient(
        Env.supabaseUrl,
        Env.supabaseAnonKey,
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
      );

  SupabaseClient? _signInClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// True once a session exists.
  bool get isSignedIn => _client.auth.currentSession != null;

  /// The signed-in reader's id, or null before any session exists —
  /// the stable identifier to link a RevenueCat purchaser to (see
  /// `PurchasesService.identify`), so entitlements follow them across
  /// devices rather than staying pinned to one install.
  String? get userId => _client.auth.currentUser?.id;

  /// Whether this session is the anonymous one [ensureSession] opens,
  /// rather than one backed by a real email identity. Drives the
  /// account section of settings: an anonymous reader is offered a
  /// backup, a linked one is shown their address.
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? false;

  /// The linked email address, or null while the session is still
  /// anonymous.
  String? get email {
    final address = _client.auth.currentUser?.email;
    return (address == null || address.isEmpty) ? null : address;
  }

  /// Guarantees a session exists, creating an anonymous one if it does
  /// not. Called once at startup, before the first frame — without it
  /// every RLS-guarded read on a fresh install comes back empty and the
  /// app looks broken rather than new.
  ///
  /// A reader who already has a session (from a previous launch, or an
  /// email they linked) keeps it: this never replaces one.
  Future<void> ensureSession() async {
    if (isSignedIn) return;
    await _run(() => _client.auth.signInAnonymously());
  }

  /// Ends the current session.
  ///
  /// **Nothing in the app calls this, and settings deliberately offers no
  /// sign-out row.** The uid *is* the shelf: for an anonymous reader
  /// there is no credential to sign back in with, so ending the session
  /// destroys their library rather than protecting it, and even for a
  /// linked one it solves a problem — "someone else uses my phone" — that
  /// a single-reader app doesn't have. Kept because it is the correct
  /// counterpart to [ensureSession] and a device-handover feature would
  /// need it; wire it to a button only alongside a way back in.
  Future<void> signOut() => _run(() => _client.auth.signOut());

  /// Attaches [email] to the *current* user and asks Supabase to mail a
  /// one-time code confirming it. Deliberately `updateUser` rather than
  /// a fresh `signInWithOtp`: the latter would provision a second
  /// account and abandon this one's shelf, whereas this keeps the same
  /// uid — see the class comment.
  ///
  /// Throws [EmailInUseException] when the address already belongs to
  /// another account — the start of the "which library?" flow.
  Future<void> linkEmail(String email) async {
    try {
      await _client.auth.updateUser(UserAttributes(email: email.trim()));
    } on AuthException catch (error) {
      if (error.code == 'email_exists' ||
          error.message.toLowerCase().contains('already been registered')) {
        throw EmailInUseException(email.trim());
      }
      throw SessionException(error.message, cause: error);
    } on Object catch (error) {
      await _run<void>(() => Future.error(error));
    }
  }

  /// Mails a sign-in code for an email that already has an account, on a
  /// separate client (see [_newSecondaryClient]). `shouldCreateUser: false`
  /// — this only ever reaches an account that exists.
  Future<void> sendSignInCode(String email) async {
    final previous = _signInClient;
    _signInClient = null;
    await previous?.dispose();
    final client = _signInClient = _newSecondaryClient();
    await _run(
      () => client.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: false,
      ),
    );
  }

  /// Confirms [sendSignInCode]'s code. The device's own session is
  /// untouched; the returned [PendingAccount] holds the email account's.
  Future<PendingAccount> verifySignInCode({
    required String email,
    required String code,
  }) async {
    final client = _signInClient;
    if (client == null) {
      throw const SessionException('Send a code first.');
    }
    final response = await _run(
      () => client.auth.verifyOTP(
        type: OtpType.email,
        email: email.trim(),
        token: code.trim(),
      ),
    );
    final session = response.session;
    if (session == null) {
      throw const SessionException('Wrong code.');
    }
    _signInClient = null;
    return PendingAccount(
      userId: session.user.id,
      email: email.trim(),
      refreshToken: session.refreshToken,
      client: client,
    );
  }

  /// What's on this device's own account.
  Future<LibrarySummary> deviceSummary() => _summary(_client);

  /// What's on [account].
  Future<LibrarySummary> accountSummary(PendingAccount account) {
    final client = account.client;
    if (client == null) {
      throw const SessionException('Sign in again.');
    }
    return _summary(client);
  }

  Future<LibrarySummary> _summary(SupabaseClient client) {
    return _run(() async {
      final rows = await client.rpc<List<dynamic>>('library_summary');
      final row = rows.isEmpty ? null : rows.first;
      if (row is! Map<String, dynamic>) {
        return const LibrarySummary(
          bookCount: 0,
          memoryCount: 0,
          eventCount: 0,
        );
      }
      return LibrarySummary.fromRow(row);
    });
  }

  /// Settles the choice: this device switches to [account]'s session, and
  /// the `link-account` edge function keeps either that account's library
  /// ([keepDevice] false) or this device's (moved onto the account), then
  /// deletes the anonymous account the device started on.
  ///
  /// The switch happens *before* the function runs. If the function then
  /// fails, nothing is lost — the anonymous account and its library still
  /// exist — and calling this again with the same [account] retries with
  /// the token captured the first time.
  Future<void> keepLibrary(
    PendingAccount account, {
    required bool keepDevice,
  }) async {
    var deviceToken = _pendingDeviceToken;
    if (deviceToken == null) {
      final current = _client.auth.currentSession;
      if (current == null) {
        throw const SessionException('Not signed in.');
      }
      if (current.user.id != account.userId) {
        final refreshed = await _run(() => _client.auth.refreshSession());
        deviceToken = refreshed.session?.accessToken ?? current.accessToken;
        _pendingDeviceToken = deviceToken;
      }
    }

    final refreshToken = account.refreshToken;
    if (_client.auth.currentUser?.id != account.userId) {
      if (refreshToken == null) {
        throw const SessionException('Sign in again.');
      }
      await _run(() => _client.auth.setSession(refreshToken));
    }

    if (deviceToken != null) {
      try {
        await _client.functions.invoke(
          'link-account',
          body: {
            'anonymous_access_token': deviceToken,
            'keep': keepDevice ? 'device' : 'account',
          },
        );
      } on FunctionException catch (error) {
        final details = error.details;
        final message = details is Map && details['error'] is String
            ? details['error'] as String
            : "Couldn't finish linking your email.";
        throw SessionException(message, cause: error);
      } on Object catch (error) {
        await _run<void>(() => Future.error(error));
      }
    }
    _pendingDeviceToken = null;
    await account.dispose();
  }

  String? _pendingDeviceToken;

  /// Confirms the code [linkEmail] mailed. [OtpType.emailChange] is the
  /// type that pairs with `updateUser(email:)`; [OtpType.email] would
  /// mean a passwordless *sign-in*, which is the account-replacing path
  /// this exists to avoid.
  Future<void> verifyEmailCode({required String email, required String code}) {
    return _run(
      () => _client.auth.verifyOTP(
        type: OtpType.emailChange,
        email: email.trim(),
        token: code.trim(),
      ),
    );
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (error) {
      // Supabase's own message is already reader-facing — no need to
      // translate it further.
      throw SessionException(error.message, cause: error);
    } on TimeoutException catch (error) {
      throw SessionException('Timed out. Try again.', cause: error);
    } on SocketException catch (error) {
      throw SessionException("You're offline.", cause: error);
    } on http.ClientException catch (error) {
      throw SessionException("Can't reach the server.", cause: error);
    }
  }
}
