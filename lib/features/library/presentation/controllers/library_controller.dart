import 'package:flutter/foundation.dart';

import '../../data/user_book_repository.dart';
import '../../domain/book.dart';
import '../../domain/book_lookup_service.dart';
import '../../domain/library_book.dart';
import '../../domain/library_exception.dart';
import '../../domain/user_book.dart';

/// Outcome of a library command, in a form the log page can show.
/// Commands never throw at the UI — failures come back as a
/// [LibraryActionResult] with `success == false` and a friendly message.
class LibraryActionResult {
  const LibraryActionResult.success([this.message]) : success = true;
  const LibraryActionResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

/// Holds the reader's shelf and applies the log-page commands to it.
///
/// The UI observes this ([ChangeNotifier]) and never talks to Supabase or
/// Google Books itself — all I/O goes through the injected service and
/// repository, which is what makes the whole feature mockable in tests.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.lookup, required this.userBooks});

  /// Cache-first title resolution (Supabase → Google Books → write-back).
  final BookLookupService lookup;

  /// Progress reads/writes.
  final UserBookRepository userBooks;

  List<LibraryBook> _books = const [];
  bool _isLoading = false;
  String? _errorMessage;

  /// Books still being read, most recently updated first.
  List<LibraryBook> get inProgress =>
      _books.where((entry) => !entry.isFinished).toList(growable: false);

  /// Completed books — rendered in their own section on the same page.
  List<LibraryBook> get finished =>
      _books.where((entry) => entry.isFinished).toList(growable: false);

  bool get isLoading => _isLoading;

  /// Set when the last *load* failed, so the page can show a retry.
  /// Command failures are reported through [LibraryActionResult] instead.
  String? get errorMessage => _errorMessage;

  bool get isEmpty => _books.isEmpty;

  /// (Re)loads the shelf from Supabase. Safe to call repeatedly; a
  /// second call while one is in flight is ignored.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _books = await userBooks.fetchLibrary();
      _errorMessage = null;
    } on LibraryException catch (error) {
      _errorMessage = error.message;
      debugPrint('LibraryController.load failed: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// `start <book>` — resolve the title cache-first, then put it on the
  /// shelf at page 0.
  ///
  /// Never creates a duplicate shelf entry — starting a book already on
  /// the shelf leaves its progress untouched — but that repeat is
  /// reported as a *failure*, not a success: nothing changed, so it
  /// shouldn't look like it did.
  Future<LibraryActionResult> startBook(String title) async {
    try {
      final book = await lookup.findOrFetch(title);
      final started = await userBooks.start(book.id);
      _upsertLocal(LibraryBook(book: book, progress: started.progress));
      notifyListeners();
      if (started.alreadyExists) {
        return LibraryActionResult.failure(
          '"${book.title}" is already on your shelf.',
        );
      }
      return LibraryActionResult.success('Started "${book.title}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `update <book> <page>` — validate the page, apply it locally so the
  /// shelf redraws immediately, then persist. If the write fails the
  /// optimistic change is rolled back, so what's on screen always
  /// matches what's stored.
  Future<LibraryActionResult> updateProgress(String title, int page) async {
    final entry = _findByTitle(title);
    if (entry == null) {
      return LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );
    }

    final validation = _validatePage(page, entry);
    if (validation != null) return LibraryActionResult.failure(validation);

    // Reaching the last page completes the book; without a known page
    // count only an explicit `finish` can.
    final total = entry.pageCount;
    final finished = total != null && page >= total;

    return _persist(
      entry,
      entry.progress.copyWith(
        currentPage: page,
        status: finished ? ReadingStatus.finished : ReadingStatus.reading,
      ),
      successMessage: finished
          ? 'Finished "${entry.book.title}"'
          : '"${entry.book.title}" — pg $page',
    );
  }

  /// `finish <book>` — mark complete and jump the page to the end when
  /// the total is known, so the finished card doesn't show a half-full
  /// bar next to a "finished" label.
  Future<LibraryActionResult> finishBook(String title) async {
    final entry = _findByTitle(title);
    if (entry == null) {
      return LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );
    }
    if (entry.isFinished) {
      return LibraryActionResult.failure(
        '"${entry.book.title}" is already finished.',
      );
    }

    return _persist(
      entry,
      entry.progress.copyWith(
        currentPage: entry.pageCount ?? entry.currentPage,
        status: ReadingStatus.finished,
        finishedAt: DateTime.now().toUtc(),
      ),
      successMessage: 'Finished "${entry.book.title}"',
    );
  }

  /// `delete <book>` — removes the book from the shelf. Optimistic like
  /// the other commands: it disappears immediately, and comes back if
  /// the delete fails to persist.
  Future<LibraryActionResult> deleteBook(String title) async {
    final entry = _findByTitle(title);
    if (entry == null) {
      return LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );
    }

    _removeLocal(entry.id);
    notifyListeners();

    try {
      await userBooks.delete(entry.id);
      return LibraryActionResult.success('Removed "${entry.book.title}"');
    } on LibraryException catch (error) {
      _upsertLocal(entry);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Optimistic write: swap the local row in, notify, then save. On
  /// failure the previous row goes back and listeners are notified again
  /// so the UI reverts rather than showing a value that never persisted.
  Future<LibraryActionResult> _persist(
    LibraryBook entry,
    UserBook updated, {
    required String successMessage,
  }) async {
    final previous = entry;
    _upsertLocal(entry.copyWith(progress: updated));
    notifyListeners();

    try {
      final saved = await userBooks.saveProgress(
        userBookId: updated.id,
        currentPage: updated.currentPage,
        finished: updated.isFinished,
      );
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      return LibraryActionResult.success(successMessage);
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Range check for a logged page. Returns null when the page is fine,
  /// or the reason it isn't.
  String? _validatePage(int page, LibraryBook entry) {
    if (page < 0) return "A page number can't be negative.";
    final total = entry.pageCount;
    if (total != null && page > total) {
      return '"${entry.book.title}" only has $total pages.';
    }
    return null;
  }

  /// Resolves what the reader typed to a book on the shelf: exact title
  /// first, then a prefix, then a substring — so "update dune 120" finds
  /// "Dune" and "update dune mess 40" finds "Dune Messiah". Ambiguous
  /// input resolves to the most recently updated match (the list is
  /// already in that order).
  LibraryBook? _findByTitle(String title) {
    final needle = title.trim().toLowerCase();
    if (needle.isEmpty) return null;

    for (final match in [
      (LibraryBook e) => e.book.title.toLowerCase() == needle,
      (LibraryBook e) => e.book.title.toLowerCase().startsWith(needle),
      (LibraryBook e) => e.book.title.toLowerCase().contains(needle),
    ]) {
      for (final entry in _books) {
        if (match(entry)) return entry;
      }
    }
    return null;
  }

  /// Inserts or replaces a shelf row, keyed on the `user_books` id.
  /// New books go to the front to match the "most recent first" order
  /// the server returns.
  void _upsertLocal(LibraryBook entry) {
    final index = _books.indexWhere((existing) => existing.id == entry.id);
    final next = [..._books];
    if (index == -1) {
      next.insert(0, entry);
    } else {
      next[index] = entry;
    }
    _books = next;
  }

  /// Removes a shelf row, keyed on the `user_books` id — the local half
  /// of [deleteBook]'s optimistic delete.
  void _removeLocal(String id) {
    _books = _books.where((existing) => existing.id != id).toList();
  }

  /// Test/debug seam: exposes the resolved catalogue entry for a title
  /// without touching the network.
  @visibleForTesting
  Book? bookForTitle(String title) => _findByTitle(title)?.book;
}
