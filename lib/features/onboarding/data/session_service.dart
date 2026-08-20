import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure from any [SessionService] call, already written for a
/// human — the UI shows [message] verbatim. The original error is kept
/// in [cause] for logging only, never rendered.
class OnboardingException implements Exception {
  const OnboardingException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'OnboardingException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Thin wrapper over `Supabase.instance.client.auth` — whether someone
/// is signed in, and the one way onboarding gets them there: a
/// passwordless email OTP, which signs in an existing account or
/// provisions a new one on first verification, so the same two calls
/// cover both the "have we met before" yes and no branches.
///
/// Every method translates Supabase/network failures into an
/// [OnboardingException] with a message safe to show directly, the same
/// way `BookCacheRepository`/`UserBookRepository` translate Postgrest
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

  /// How old the just-verified account actually is — near-zero for a
  /// brand new signup, much larger when the email already had an
  /// account before this OTP verification. There's no dedicated
  /// "does this email exist" API (Supabase deliberately doesn't expose
  /// one, to avoid leaking account existence), so this is the only
  /// signal available: `verifyEmailCode` succeeds identically either
  /// way, but the resulting user's `createdAt` only predates "now" by a
  /// few seconds for a genuinely new account.
  Duration? get accountAge {
    final createdAt = _client.auth.currentUser?.createdAt;
    if (createdAt == null) return null;
    return DateTime.now().toUtc().difference(DateTime.parse(createdAt).toUtc());
  }

  /// Whether the reader who just verified an OTP code already had an
  /// account before doing so — see [accountAge]. Used on the "no, I
  /// don't have an account" path to catch a reader who was wrong about
  /// that (see `WeKnowYouPage`).
  bool get isExistingAccount {
    final age = accountAge;
    return age != null && age > const Duration(seconds: 20);
  }

  /// Ends the current session — used when a reader on the "no" path
  /// turns out to already have an account (see `WeKnowYouPage`) and
  /// wants to back out and try a different email, rather than staying
  /// signed into the account they weren't expecting.
  Future<void> signOut() => _run(() => _client.auth.signOut());

  /// Generates a 6-digit OTP token and instructs Supabase to deliver it
  /// directly to the user's inbox using Resend. If the email doesn't exist yet,
  /// it provisions a new user record natively upon verification.
  Future<void> sendEmailConfirmation(String email) {
    return _run(
      () => _client.auth.signInWithOtp(
        email: email,
        // DO NOT supply a redirectTo option here to avoid generating link metadata parameters
      ),
    );
  }

  /// Verifies the raw 6-digit code received via Resend. This processes a passwordless
  /// authentication state and initializes a secure session token inside your application.
  Future<void> verifyEmailCode({required String email, required String code}) {
    return _run(
      () => _client.auth.verifyOTP(
        type: OtpType
            .email, // Crucial: Switch from 'emailChange' to 'email' for passwordless OTP workflows
        email: email,
        token: code,
      ),
    );
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (error) {
      // Supabase's own message is already reader-facing — no need to
      // translate it further.
      throw OnboardingException(error.message, cause: error);
    } on TimeoutException catch (error) {
      throw OnboardingException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OnboardingException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw OnboardingException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    }
  }
}
