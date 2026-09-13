import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/env/env.dart';
import '../domain/library_exception.dart';
import 'google_book.dart';

/// Thin wrapper over the Google Books "volumes" search endpoint. Takes
/// its [http.Client] by injection so it can be swapped for a mock in
/// tests instead of hitting the network.
///
/// Every failure mode — offline, timeout, non-200, malformed body — is
/// translated into a [LibraryException] here, so callers never have to
/// know about sockets or status codes.
class GoogleBooksApiClient {
  GoogleBooksApiClient({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 12);

  final http.Client _client;

  /// Hard ceiling on a single request. Google Books is normally fast;
  /// a stalled connection must not leave the search spinner up forever.
  final Duration _timeout;

  static const _baseUrl = 'https://www.googleapis.com/books/v1/volumes';

  /// Searches volumes for [query].
  ///
  /// Throws [InvalidInputException] for an empty query, [NetworkException]
  /// for offline/timeout/5xx, and [RemoteDataException] for a response
  /// we cannot parse or that the API rejected (4xx — bad key, quota).
  Future<List<GoogleBook>> search(String query, {int maxResults = 10}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const InvalidInputException('Enter a book title to search for.');
    }

    final uri = _uri(_baseUrl, {
      'q': trimmed,
      // Google caps maxResults at 40; keep the request inside that.
      'maxResults': '${maxResults.clamp(1, 40)}',
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
      throw RemoteDataException(
        'Google Books sent back something we could not read.',
        cause: error,
      );
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
      throw const InvalidInputException("That book doesn't have a Google id.");
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
      throw RemoteDataException(
        'Google Books sent back something we could not read.',
        cause: error,
      );
    }
  }

  Uri _uri(String base, Map<String, String> query) {
    final apiKey = Env.googleBooksApiKeyOrNull;
    return Uri.parse(base).replace(queryParameters: {...query, 'key': ?apiKey});
  }

  /// One GET, with every transport/status/parse failure translated into a
  /// [LibraryException]. [subject] names the request in the user-facing
  /// timeout message ("Book search timed out", "Book info timed out").
  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String subject,
  }) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException catch (error) {
      throw NetworkException(
        '$subject timed out. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw NetworkException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw NetworkException(
        "We couldn't reach Google Books. Try again in a moment.",
        cause: error,
      );
    }

    if (response.statusCode >= 500 || response.statusCode == 429) {
      // Server-side or rate-limited, and therefore worth retrying later.
      throw NetworkException(
        'Google Books is having trouble right now. Try again shortly.',
        cause: 'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    if (response.statusCode == 404) {
      throw BookNotFoundException(
        "Google Books doesn't have that book any more.",
        cause: 'HTTP 404: ${response.body}',
      );
    }
    if (response.statusCode != 200) {
      // 4xx: bad key, malformed query — retrying the same call will not
      // help, so this is a data/config error.
      throw RemoteDataException(
        "Book search isn't available right now.",
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
      throw RemoteDataException(
        'Google Books sent back something we could not read.',
        cause: error,
      );
    }
  }

  void dispose() => _client.close();
}
