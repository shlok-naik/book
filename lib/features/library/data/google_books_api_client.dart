import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env/env.dart';
import '../domain/library_exception.dart';
import 'google_book.dart';

/// Thin wrapper over the Google Books "volumes" API, reached through the
/// `google-books` Supabase edge function rather than googleapis.com
/// directly — the function adds the API key server-side, so no key ships in
/// the app (see `supabase/functions/google-books/index.ts`). The function
/// mirrors Google's own paths and passes its status and body through, so
/// everything below parses exactly what Google sent.
///
/// Takes its [http.Client] by injection so it can be swapped for a mock in
/// tests instead of hitting the network.
///
/// Every failure mode — offline, timeout, non-200, malformed body — is
/// translated into a [LibraryException] here, so callers never have to
/// know about sockets or status codes.
class GoogleBooksApiClient {
  GoogleBooksApiClient({
    http.Client? client,
    Duration? timeout,
    Future<Map<String, String>> Function()? authHeaders,
    List<Duration>? retryDelays,
  }) : _client = client ?? http.Client(),
       _timeout = timeout ?? const Duration(seconds: 12),
       _authHeaders = authHeaders ?? _sessionHeaders,
       _retryDelays = retryDelays ?? defaultRetryDelays;

  /// How long to wait before each retry of a request Google answered with a
  /// 503/5xx or 429. Google Books sheds load with a fast 503 — the logs show
  /// bursts of them within a second of each other (an import's parallel
  /// lookups, a recommendation row), mostly gone a moment later — so a short
  /// back-off turns most of them into answers instead of error messages.
  static const defaultRetryDelays = [
    Duration(milliseconds: 600),
    Duration(milliseconds: 1500),
  ];

  final List<Duration> _retryDelays;

  final http.Client _client;

  /// Hard ceiling on a single request. Google Books is normally fast;
  /// a stalled connection must not leave the search spinner up forever.
  final Duration _timeout;

  /// The signed-in session's headers for the edge function — injectable
  /// so tests never reach for an uninitialised Supabase client.
  final Future<Map<String, String>> Function() _authHeaders;

  /// `<project>/functions/v1/google-books/volumes`. Resolved per request so
  /// a test (which never configures Supabase) still builds a URL; the mock
  /// client it injects never sends it anywhere.
  static String get _baseUrl {
    final project = Env.supabaseUrlOrNull ?? 'https://supabase.invalid';
    return '$project/functions/v1/google-books/volumes';
  }

  /// The caller's access token, refreshed first if it has lapsed (an app
  /// left in the background past the token's hour), plus the project's
  /// publishable key. Empty when there's no Supabase client or session —
  /// the function then answers 401, reported like any refused request.
  static Future<Map<String, String>> _sessionHeaders() async {
    try {
      final auth = Supabase.instance.client.auth;
      var session = auth.currentSession;
      if (session != null && session.isExpired) {
        session = (await auth.refreshSession()).session ?? session;
      }
      final token = session?.accessToken;
      final publishableKey = Env.supabaseAnonKeyOrNull;
      return {
        'Authorization': ?(token == null ? null : 'Bearer $token'),
        'apikey': ?publishableKey,
      };
    } on Object {
      return const {};
    }
  }

  /// Searches volumes for [query].
  ///
  /// Throws [InvalidInputException] for an empty query, [NetworkException]
  /// for offline/timeout/5xx, and [RemoteDataException] for a response
  /// we cannot parse or that the API rejected (4xx — bad key, quota).
  Future<List<GoogleBook>> search(
    String query, {
    int maxResults = 10,
    String? orderBy,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const InvalidInputException('Enter a title.');
    }

    final uri = _uri(_baseUrl, {
      'q': trimmed,
      // Google caps maxResults at 40; keep the request inside that.
      'maxResults': '${maxResults.clamp(1, 40)}',
      'orderBy': ?orderBy,
    });

    final body = await _getJson(uri, subject: 'Book search');
    try {
      final items = (body['items'] as List<dynamic>?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(GoogleBook.fromJson)
          // A volume with no id cannot be cached or de-duplicated, so
          // drop it rather than writing an unmatchable cache row.
          .where((book) => book.id.isNotEmpty)
          .toList();
    } on TypeError catch (error) {
      throw RemoteDataException('Google Books error.', cause: error);
    }
  }

  /// Fetches one volume by its Google Books id — the full record, which
  /// (unlike a search result) carries the complete description, categories
  /// and ratings the book detail page shows.
  ///
  /// Same error contract as [search], plus [BookNotFoundException] for a
  /// 404: the volume was withdrawn from Google Books after we cached it.
  Future<GoogleBook> fetchVolume(String googleBooksId) async {
    final id = googleBooksId.trim();
    if (id.isEmpty) {
      throw const InvalidInputException('No Google id.');
    }

    final uri = _uri('$_baseUrl/${Uri.encodeComponent(id)}', const {});
    final body = await _getJson(uri, subject: 'Book info');
    try {
      final volume = GoogleBook.fromJson(body);
      if (volume.id.isEmpty) {
        throw const FormatException('Volume without an id.');
      }
      return volume;
    } on Object catch (error) {
      if (error is LibraryException) rethrow;
      throw RemoteDataException('Google Books error.', cause: error);
    }
  }

  Uri _uri(String base, Map<String, String> query) =>
      Uri.parse(base).replace(queryParameters: query.isEmpty ? null : query);

  /// One attempt at [uri], transport failures translated.
  Future<http.Response> _send(Uri uri, {required String subject}) async {
    try {
      return await _client
          .get(uri, headers: await _authHeaders())
          .timeout(_timeout);
    } on TimeoutException catch (error) {
      throw NetworkException('$subject timed out.', cause: error);
    } on SocketException catch (error) {
      throw NetworkException("You're offline.", cause: error);
    } on http.ClientException catch (error) {
      throw NetworkException("Can't reach Google Books.", cause: error);
    }
  }

  /// One GET, with every transport/status/parse failure translated into a
  /// [LibraryException]. [subject] names the request in the user-facing
  /// timeout message ("Book search timed out", "Book info timed out").
  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String subject,
  }) async {
    var response = await _send(uri, subject: subject);
    for (final delay in _retryDelays) {
      if (response.statusCode < 500 && response.statusCode != 429) break;
      await Future<void>.delayed(delay);
      response = await _send(uri, subject: subject);
    }

    // The edge function passes Google's status through; its own 504 (Google
    // didn't answer) lands in the retryable branch with Google's 5xx.
    if (response.statusCode >= 500 || response.statusCode == 429) {
      // Server-side or rate-limited, and therefore worth retrying later.
      throw NetworkException(
        'Google Books is busy. Try again.',
        cause: 'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    if (response.statusCode == 404) {
      throw BookNotFoundException(
        'Book no longer on Google Books.',
        cause: 'HTTP 404: ${response.body}',
      );
    }
    if (response.statusCode != 200) {
      // 4xx: bad key, malformed query — retrying the same call will not
      // help, so this is a data/config error.
      throw RemoteDataException(
        'Search unavailable.',
        cause: 'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object at the root.');
      }
      return body;
    } on FormatException catch (error) {
      throw RemoteDataException('Google Books error.', cause: error);
    }
  }

  void dispose() => _client.close();
}
