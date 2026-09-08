import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
  SessionService({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

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
  Future<void> linkEmail(String email) {
    return _run(
      () => _client.auth.updateUser(UserAttributes(email: email.trim())),
    );
  }

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
      throw SessionException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw SessionException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw SessionException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    }
  }
}
