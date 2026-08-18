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
        type: OtpType.email, // Crucial: Switch from 'emailChange' to 'email' for passwordless OTP workflows
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
