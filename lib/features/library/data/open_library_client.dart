import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/library_exception.dart';
import 'google_book.dart';

/// Open Library ([docs](https://openlibrary.org/developers/api)) — the
/// backup for Google Books. It needs no key and has no daily quota, so when
/// Google refuses (its keyless quota runs out daily, answering 429/503) the
/// app searches here instead, and it fills in covers Google doesn't have.
///
/// Results come back as [GoogleBook]s so nothing downstream changes: the id
/// is `ol:<work key>` (e.g. `ol:OL45804W`), which `cache_book` stores like
/// any other id, the cover is `covers.openlibrary.org/b/id/<cover_i>-M.jpg`,
/// and `ratings_count` stands in for Google's so popularity sorting still
/// works.
///
/// Everything is cached in memory: a search for [searchTtl], a cover lookup
/// (found or not) for the life of the app — covers never change and a miss
/// is worth remembering too.
class OpenLibraryClient {
  OpenLibraryClient({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 10);

  final http.Client _client;
  final Duration _timeout;

  static const idPrefix = 'ol:';
  static const searchTtl = Duration(minutes: 30);
  static const _maxSearches = 60;
  static const _fields =
      'key,title,subtitle,author_name,cover_i,isbn,number_of_pages_median,'
      'first_publish_year,subject,publisher,language,ratings_average,'
      'ratings_count';

  /// Open Library asks callers to identify themselves.
  static const _headers = {'User-Agent': 'cactus-reading-app/1.0'};

  final _searches = <String, ({DateTime at, List<GoogleBook> books})>{};
  final _covers = <String, String?>{};
  final _inFlightCovers = <String, Future<String?>>{};

  static bool isOpenLibraryId(String id) => id.startsWith(idPrefix);

  static String coverUrl(int coverId) =>
      'https://covers.openlibrary.org/b/id/$coverId-M.jpg?default=false';

  /// Searches with a Google Books–style [query]: `inauthor:"x"`,
  /// `intitle:"x"`, `subject:"x"` and `isbn:x` become Open Library's own
  /// fields, anything left over is free text. [newest] sorts by publication.
  Future<List<GoogleBook>> search(
    String query, {
    int limit = 20,
    bool newest = false,
  }) async {
    final params = translate(query)
      ..['limit'] = '${limit.clamp(1, 50)}'
      ..['fields'] = _fields;
    if (newest) params['sort'] = 'new';
    final key = Uri(queryParameters: params).query;

    final cached = _searches[key];
    if (cached != null && DateTime.now().difference(cached.at) < searchTtl) {
      return cached.books;
    }

    final uri = Uri.https('openlibrary.org', '/search.json', params);
    final body = await _getJson(uri);
    final docs = body['docs'];
    final books = [
      if (docs is List)
        for (final doc in docs)
          if (doc is Map<String, dynamic>) ?fromDoc(doc),
    ];
    _searches[key] = (at: DateTime.now(), books: books);
    while (_searches.length > _maxSearches) {
      _searches.remove(_searches.keys.first);
    }
    return books;
  }

  /// A cover for a book Google had none for: by ISBN first (the cover of
  /// that exact printing), else by title and author. Null when Open Library
  /// has none either. Cached, and concurrent asks for one book share a call.
  Future<String?> coverFor({
    String? isbn,
    required String title,
    String? author,
  }) {
    final clean = isbn?.replaceAll(RegExp('[^0-9Xx]'), '');
    final key = (clean != null && clean.isNotEmpty)
        ? 'isbn:$clean'
        : 'title:${title.toLowerCase()}|${author?.toLowerCase() ?? ''}';
    if (_covers.containsKey(key)) return Future.value(_covers[key]);
    return _inFlightCovers[key] ??=
        _lookUpCover(
          key,
          isbn: clean,
          title: title,
          author: author,
        ).whenComplete(() {
          // A block, not an arrow: `remove` returns this very future, and
          // whenComplete would wait on it — forever.
          _inFlightCovers.remove(key);
        });
  }

  Future<String?> _lookUpCover(
    String key, {
    String? isbn,
    required String title,
    String? author,
  }) async {
    String? url;
    try {
      if (isbn != null && isbn.isNotEmpty) {
        url = await _coverFrom({'isbn': isbn});
      }
      // An ISBN Open Library has no cover for — often a newer printing —
      // still gets the work's cover by title.
      url ??= await _coverFrom({
        'title': title,
        if (author != null && author.isNotEmpty && author != 'Unknown author')
          'author': author,
      });
    } on LibraryException {
      // Don't remember a failure — only an answer.
      return null;
    }
    _covers[key] = url;
    return url;
  }

  Future<String?> _coverFrom(Map<String, String> query) async {
    final body = await _getJson(
      Uri.https('openlibrary.org', '/search.json', {
        ...query,
        'limit': '1',
        'fields': 'cover_i',
      }),
    );
    final docs = body['docs'];
    if (docs is List && docs.isNotEmpty && docs.first is Map) {
      final coverId = (docs.first as Map)['cover_i'];
      if (coverId is int) return coverUrl(coverId);
    }
    return null;
  }

  /// Google Books query syntax → Open Library search parameters.
  static Map<String, String> translate(String query) {
    final params = <String, String>{};
    var rest = query;
    final field = RegExp(
      r'(inauthor|intitle|subject|isbn):(?:"([^"]*)"|(\S+))',
    );
    for (final match in field.allMatches(query)) {
      final value = (match.group(2) ?? match.group(3) ?? '').trim();
      final name = switch (match.group(1)) {
        'inauthor' => 'author',
        'intitle' => 'title',
        'subject' => 'subject',
        _ => 'isbn',
      };
      if (value.isNotEmpty) params[name] = value;
      rest = rest.replaceFirst(match.group(0)!, ' ');
    }
    rest = rest.replaceAll('"', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (rest.isNotEmpty) params['q'] = rest;
    return params;
  }

  /// One search result → a [GoogleBook], or null without a key or title.
  static GoogleBook? fromDoc(Map<String, dynamic> doc) {
    final key = doc['key'];
    final title = doc['title'];
    if (key is! String || title is! String || title.trim().isEmpty) {
      return null;
    }
    List<String> strings(Object? value, [int max = 20]) => [
      if (value is List)
        for (final item in value.take(max))
          if (item is String && item.trim().isNotEmpty) item,
    ];
    final isbns = strings(doc['isbn'], 50);
    final coverId = doc['cover_i'];
    final year = doc['first_publish_year'];
    final pages = doc['number_of_pages_median'];
    final rating = doc['ratings_average'];
    final ratings = doc['ratings_count'];
    return GoogleBook(
      id: '$idPrefix${key.split('/').last}',
      title: title.trim(),
      authors: strings(doc['author_name'], 5),
      subtitle: doc['subtitle'] is String ? doc['subtitle'] as String : null,
      thumbnailUrl: coverId is int ? coverUrl(coverId) : null,
      pageCount: pages is int && pages > 0 ? pages : null,
      publishedDate: year is int ? '$year' : null,
      publisher: strings(doc['publisher'], 1).firstOrNull,
      language: strings(doc['language'], 1).firstOrNull,
      categories: strings(doc['subject'], 5),
      isbn13: isbns.where((i) => i.length == 13).firstOrNull,
      isbn10: isbns.where((i) => i.length == 10).firstOrNull,
      averageRating: rating is num ? rating.toDouble() : null,
      ratingsCount: ratings is int ? ratings : null,
      printType: 'BOOK',
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(_timeout);
    } on TimeoutException catch (error) {
      throw NetworkException('Timed out. Try again.', cause: error);
    } on SocketException catch (error) {
      throw NetworkException("You're offline.", cause: error);
    } on http.ClientException catch (error) {
      throw NetworkException("Can't reach Open Library.", cause: error);
    }
    if (response.statusCode != 200) {
      throw NetworkException(
        'Book search is busy. Try again.',
        cause: 'Open Library HTTP ${response.statusCode}',
      );
    }
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
      throw const FormatException('Expected a JSON object.');
    } on FormatException catch (error) {
      throw RemoteDataException('Book search error.', cause: error);
    }
  }
}
