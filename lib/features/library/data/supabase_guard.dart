import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
    return await action().timeout(timeout);
  } on LibraryException {
    // Already translated further down (e.g. by a row parser) — keep the
    // more specific message instead of flattening it here.
    rethrow;
  } on TimeoutException catch (error) {
    throw NetworkException(
      'The library took too long to respond. Try again.',
      cause: error,
    );
  } on SocketException catch (error) {
    throw NetworkException(
      "You're offline — connect to the internet and try again.",
      cause: error,
    );
  } on http.ClientException catch (error) {
    throw NetworkException(
      "We couldn't reach your library. Try again in a moment.",
      cause: error,
    );
  } on PostgrestException catch (error) {
    // Postgrest reports transport-ish failures with a 5xx-style code;
    // those are worth retrying, everything else (bad column, RLS denial,
    // constraint violation) is not.
    final code = int.tryParse(error.code ?? '');
    if (code != null && code >= 500) {
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
