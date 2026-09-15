import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../library/domain/book.dart';
import '../../../library/domain/book_lookup_service.dart';
import '../../../library/domain/collections.dart';
import '../../../library/domain/library_exception.dart';
import '../../../library/domain/user_book.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../data/library_transfer_repository.dart';
import '../../domain/goodreads_import.dart';

enum ImportStage { idle, matching, review, importing, done, failed }

/// One file row that couldn't be matched to a book.
typedef UnmatchedRow = ({ImportRow row, String reason});

/// Runs a Goodreads import from a picked file to a replaced library:
///
/// 1. **matching** — every row is resolved to a catalogue book, ISBN first,
///    then title and author, a few at a time. Nothing on the shelf has
///    changed yet, and the reader can cancel.
/// 2. **review** — how many matched, which didn't, and what the replace
///    will delete. Still nothing changed.
/// 3. **importing** — the file's tags are made first, then one
///    `replace_library` call swaps the library in a single transaction
///    (linking only tags that exist), then the shelf is reloaded and
///    series found in the file are made and filed against the freshly
///    imported rows (best-effort — a series name that fails to make is
///    logged and that row's series skipped, never the whole import).
///
/// Tags and series follow the app's make-first rule even here: the import
/// makes them through the same creation paths as `make tag` and
/// `make series` (`CollectionsRepository.createTag`,
/// `LibraryController.makeSeries`) and only then applies them — nothing
/// downstream invents one while adding a book.
/// 4. **done** / **failed** — either way the shelf is reloaded, so what the
///    app shows is what the server actually holds.
class ImportController extends ChangeNotifier {
  ImportController({
    required this.lookup,
    required this.transfer,
    required this.library,
    this.concurrency = 4,
    this.retryDelay = const Duration(milliseconds: 1500),
  });

  final BookLookupService lookup;
  final LibraryTransferRepository transfer;
  final LibraryController library;
  final int concurrency;
  final Duration retryDelay;

  ImportStage _stage = ImportStage.idle;
  List<ImportRow> _rows = const [];
  final _matched = <(ImportRow, Book)>[];
  final _unmatched = <UnmatchedRow>[];
  int _duplicates = 0;
  int _skipped = 0;
  int _done = 0;
  int _imported = 0;
  String? _error;
  bool _disposed = false;

  /// Bumped by every [start] and [cancel]; a matching run that finds it
  /// changed has been abandoned and stops touching state.
  int _generation = 0;

  ImportStage get stage => _stage;
  int get total => _rows.length;
  int get processed => _done;
  List<(ImportRow, Book)> get matched => List.unmodifiable(_matched);
  List<UnmatchedRow> get unmatched => List.unmodifiable(_unmatched);

  /// Rows naming a book already matched by an earlier row.
  int get duplicates => _duplicates;

  /// Rows with no title at all.
  int get skipped => _skipped;

  int get imported => _imported;
  String? get errorMessage => _error;

  /// Parses [csv] and matches every row. Ends in [ImportStage.review], or
  /// [ImportStage.failed] for a file that isn't a library export.
  Future<void> start(String csv) async {
    _reset();
    final run = ++_generation;
    final ImportParseResult parsed;
    try {
      parsed = GoodreadsImport.parse(csv);
    } on ImportFormatException catch (error) {
      _fail(error.message);
      return;
    }
    if (parsed.rows.isEmpty) {
      _fail('There are no books in that file.');
      return;
    }

    _rows = parsed.rows;
    _skipped = parsed.skipped;
    _stage = ImportStage.matching;
    _notify();

    final results = List<Book?>.filled(_rows.length, null);
    final reasons = List<String?>.filled(_rows.length, null);
    var next = 0;

    Future<void> worker() async {
      final rows = _rows;
      while (run == _generation && !_disposed && next < rows.length) {
        final index = next++;
        try {
          results[index] = await _match(rows[index]);
        } on LibraryException catch (error) {
          reasons[index] = error is BookNotFoundException
              ? 'not found'
              : error.message;
        }
        if (run != _generation) return;
        _done++;
        _notify();
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    if (run != _generation || _disposed) return;

    final seen = <String>{};
    for (var i = 0; i < _rows.length; i++) {
      final book = results[i];
      if (book == null) {
        _unmatched.add((row: _rows[i], reason: reasons[i] ?? 'not found'));
      } else if (!seen.add(book.id)) {
        _duplicates++;
      } else {
        _matched.add((_rows[i], book));
      }
    }
    _stage = ImportStage.review;
    _notify();
  }

  /// Stops matching; the library is untouched.
  void cancel() {
    if (_stage != ImportStage.matching) return;
    _generation++;
    _reset();
    _notify();
  }

  /// Replaces the library with every matched book. Only valid in
  /// [ImportStage.review].
  Future<void> confirm() async {
    if (_stage != ImportStage.review) return;
    if (_matched.isEmpty) {
      _fail('None of the books in that file could be found.');
      return;
    }
    _stage = ImportStage.importing;
    _notify();

    await _makeTags();

    try {
      _imported = await transfer.replaceLibrary([
        for (final (row, book) in _matched) toImported(row, book),
      ]);
    } on LibraryException catch (error) {
      AppLogger.error('ImportController', 'Import failed.', error: error);
      await _reloadQuietly();
      _fail(error.message);
      return;
    }

    // Marks every imported row and stamps the import time — the baseline
    // the stats page counts monthly charts and pace from. Best-effort: the
    // library itself is already replaced, and a failure here only means the
    // imported books still count in the monthly charts, so it's logged
    // rather than reported as a failed import.
    try {
      await transfer.markImported();
    } on LibraryException catch (error) {
      AppLogger.warning(
        'ImportController',
        'Could not mark the import baseline.',
        error: error,
      );
    }

    // The freshly imported rows are what `addToSeries` matches on by
    // title, and their series must already be on the reader's own list.
    await _reloadQuietly();

    for (final (row, book) in _matched) {
      final name = row.series;
      if (name == null || name.trim().isEmpty) continue;
      if (library.findSeries(name) == null) {
        // Import is only reachable once a reader is pro (gated in
        // Settings, see `_LibraryDataSection`) — the 1-series free cap
        // never applies here.
        final made = await library.makeSeries(name, isPro: true);
        if (!made.success) {
          AppLogger.info(
            'ImportController',
            'Skipped making an imported series: ${made.message}',
          );
          continue;
        }
      }
      final filed = await library.addToSeries(
        book.title,
        name,
        position: row.seriesPosition,
      );
      if (!filed.success) {
        AppLogger.info(
          'ImportController',
          'Skipped filing an imported series: ${filed.message}',
        );
      }
    }

    _stage = ImportStage.done;
    _notify();
  }

  /// Makes every tag named in the matched rows that the reader doesn't have
  /// yet, so `replace_library` has something to link. Best-effort per tag,
  /// like series: a name that can't be made is logged and that tag skipped,
  /// never the whole import.
  Future<void> _makeTags() async {
    final wanted = <String, String>{};
    for (final (row, _) in _matched) {
      for (final tag in row.tags) {
        final key = CollectionNames.key(tag);
        if (key.isNotEmpty) wanted.putIfAbsent(key, () => tag);
      }
    }
    final existing = {
      for (final tag in library.tags) CollectionNames.key(tag.name),
    };
    for (final MapEntry(key: key, value: name) in wanted.entries) {
      if (existing.contains(key)) continue;
      try {
        await library.collections.createTag(name);
      } on LibraryException catch (error) {
        AppLogger.info(
          'ImportController',
          'Skipped making an imported tag: ${error.message}',
        );
      }
    }
  }

  /// Back to [ImportStage.idle], for another file.
  void reset() {
    _reset();
    _notify();
  }

  /// How one matched row lands on the shelf — see [GoodreadsImport] for
  /// where each value comes from.
  @visibleForTesting
  static ImportedBook toImported(ImportRow row, Book book) {
    final length = book.pageCount ?? row.pages;
    int clampPage(int page) {
      if (page < 0) return 0;
      return length != null && page > length ? length : page;
    }

    final page = switch (row.status) {
      ReadingStatus.finished => length ?? row.currentPage ?? 0,
      ReadingStatus.reading ||
      ReadingStatus.dnf => clampPage(row.currentPage ?? 0),
      ReadingStatus.toBeRead => 0,
    };
    return ImportedBook(
      bookId: book.id,
      status: row.status,
      currentPage: page,
      rating: row.rating,
      startedAt: row.dateAdded,
      finishedAt: row.status == ReadingStatus.finished ? row.dateRead : null,
      tags: row.tags,
      comments: row.comments,
    );
  }

  Future<Book> _match(ImportRow row) async {
    return _withRetry(() async {
      final isbn = row.isbn;
      if (isbn != null) {
        try {
          return await lookup.findOrFetchByIsbn(isbn);
        } on BookNotFoundException {
          // Fall through to the title: Google often lacks older ISBNs.
        } on InvalidInputException {
          // Same.
        }
      }
      return lookup.findOrFetch(
        row.title,
        author: row.author.isEmpty ? null : row.author,
      );
    });
  }

  /// One retry after a pause for a network hiccup or Google Books' rate
  /// limit, which a few hundred rows can easily hit.
  Future<Book> _withRetry(Future<Book> Function() action) async {
    try {
      return await action();
    } on NetworkException {
      if (_disposed) rethrow;
      await Future<void>.delayed(retryDelay);
      return action();
    }
  }

  Future<void> _reloadQuietly() async {
    try {
      await library.reset();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ImportController',
        'Reloading the library after an import failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _reset() {
    _stage = ImportStage.idle;
    _rows = const [];
    _matched.clear();
    _unmatched.clear();
    _duplicates = 0;
    _skipped = 0;
    _done = 0;
    _imported = 0;
    _error = null;
  }

  void _fail(String message) {
    _stage = ImportStage.failed;
    _error = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
