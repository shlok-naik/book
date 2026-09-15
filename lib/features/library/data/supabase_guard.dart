import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/connectivity_controller.dart';
import '../../../core/supabase/postgrest_failure.dart';
import '../domain/library_exception.dart';

/// Default ceiling for a single Supabase round-trip. The cache exists to
/// make lookups feel instant; if it can't answer quickly there is no
/// point waiting — the caller falls through to Google Books.
const supabaseTimeout = Duration(seconds: 10);

/// Runs a Supabase call with a timeout and translates everything it can
/// throw into a [LibraryException] carrying a user-safe message.
///
/// [friendlyMessage] is what the user sees; the raw driver error is kept
/// only in [LibraryException.cause] for logs.
///
/// Note the broad `on Object` fallback: besides the network and
/// Postgrest errors below, `Supabase.instance` throws an [AssertionError]
/// (an Error, not an Exception) when the client was never initialized.
/// That must degrade to a visible error message, not a crash.
Future<T> runSupabase<T>(
  Future<T> Function() action, {
  required String friendlyMessage,
  Duration timeout = supabaseTimeout,
}) async {
  try {
    final result = await action().timeout(timeout);
    // Any answer at all proves the backend is reachable — tells the
    // offline indicator the moment a request gets through, without
    // waiting for its next probe. A no-op unless connectivity is attached.
    ConnectivityController.reportReachable();
    return result;
  } on LibraryException {
    // Already translated further down (e.g. by a row parser) — keep the
    // more specific message instead of flattening it here.
    rethrow;
  } on TimeoutException catch (error) {
    ConnectivityController.reportUnreachable();
    throw NetworkException(
      'The library took too long to respond. Try again.',
      cause: error,
    );
  } on SocketException catch (error) {
    ConnectivityController.reportUnreachable();
    throw NetworkException(
      "You're offline — connect to the internet and try again.",
      cause: error,
    );
  } on http.ClientException catch (error) {
    ConnectivityController.reportUnreachable();
    throw NetworkException(
      "We couldn't reach your library. Try again in a moment.",
      cause: error,
    );
  } on PostgrestException catch (error) {
    // Only a server that couldn't serve the request is worth retrying (and
    // queueing offline); a refusal — bad column, RLS denial, constraint
    // violation — is not. See [isTransientPostgrestError]: the code is a
    // SQLSTATE, so `23505` must not read as a 5xx.
    if (isTransientPostgrestError(error)) {
      throw NetworkException(friendlyMessage, cause: error);
    }
    throw RemoteDataException(friendlyMessage, cause: error);
  } on Object catch (error) {
    throw RemoteDataException(friendlyMessage, cause: error);
  }
}

/// Escapes the wildcards Postgres `LIKE`/`ILIKE` treats as operators, so
/// a title containing `%` or `_` (e.g. "100% Dune") matches literally
/// instead of turning into a match-anything pattern.
String escapeLikePattern(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
