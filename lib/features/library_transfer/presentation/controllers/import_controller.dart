import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../library/data/book_series_repository.dart';
import '../../../library/domain/book.dart';
import '../../../library/domain/book_lookup_service.dart';
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
/// 3. **importing** — one `replace_library` call swaps the library in a
///    single transaction, then series found in the file are filed
///    (best-effort — a series another reader already set is left alone).
/// 4. **done** / **failed** — either way the shelf is reloaded, so what the
///    app shows is what the server actually holds.
class ImportController extends ChangeNotifier {
  ImportController({
    required this.lookup,
    required this.transfer,
    required this.series,
    required this.library,
    this.concurrency = 4,
    this.retryDelay = const Duration(milliseconds: 1500),
  });

  final BookLookupService lookup;
  final LibraryTransferRepository transfer;
  final BookSeriesRepository series;
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

    for (final (row, book) in _matched) {
      final name = row.series;
      if (name == null || name.trim().isEmpty) continue;
      try {
        await series.setSeries(book.id, name, position: row.seriesPosition);
      } on LibraryException catch (error) {
        AppLogger.info(
          'ImportController',
          'Skipped filing an imported series: ${error.message}',
        );
      }
    }

    await _reloadQuietly();
    _stage = ImportStage.done;
    _notify();
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
