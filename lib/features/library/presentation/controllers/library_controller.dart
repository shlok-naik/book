import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../data/reading_event_repository.dart';
import '../../data/user_book_repository.dart';
import '../../domain/book.dart';
import '../../domain/book_lookup_service.dart';
import '../../domain/library_book.dart';
import '../../domain/library_exception.dart';
import '../../domain/reading_event.dart';
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
  LibraryController({
    required this.lookup,
    required this.userBooks,
    ReadingEventRepository? events,
  }) : events = events ?? ReadingEventRepository();

  /// Cache-first title resolution (Supabase → Google Books → write-back).
  final BookLookupService lookup;

  /// Progress reads/writes.
  final UserBookRepository userBooks;

  /// Per-command history for the streaks page. Optional at construction
  /// (defaults to a real repository) so existing callers/tests that only
  /// care about shelf state don't have to know this exists.
  final ReadingEventRepository events;

  final _loggedEvents = StreamController<ReadingEvent>.broadcast();

  /// Every [ReadingEvent] that has actually been persisted, in the order
  /// it landed. The streaks feature listens to this to update its own
  /// state directly — this stream carries only the one thing that
  /// changed, unlike this class's own [notifyListeners] (a "the shelf
  /// changed somehow" signal that would otherwise force a full-year
  /// Supabase refetch on every single shelf command).
  Stream<ReadingEvent> get loggedEvents => _loggedEvents.stream;

  /// Records [type] without letting a logging failure affect the shelf
  /// command it came from — the pill has already reported success or
  /// failure by the time this runs, so nothing here can change that.
  ///
  /// Broadcasts on [loggedEvents] once the write actually lands — not
  /// before, so a listener never learns about an event that failed to
  /// persist.
  ///
  /// [occurredAt] backdates the event — "I started Dune yesterday" —
  /// instead of logging it as happening right now; see
  /// [ReadingEventRepository.log]. Local-time midnight on the given day
  /// when it comes from [ParsedLogCommand.date], converted to UTC here
  /// alongside the "now" case so every path through this method ends up
  /// storing the same UTC representation.
  void _logEvent(ReadingEventType type, String title, {DateTime? occurredAt}) {
    final at = (occurredAt ?? DateTime.now()).toUtc();
    final event = ReadingEvent(type: type, occurredAt: at, title: title);
    reportingFailure(
      events
          .log(type, title: title, occurredAt: at)
          .then((_) => _loggedEvents.add(event)),
      source: 'LibraryController',
      message: 'Could not record a "${type.wireValue}" reading event.',
    );
  }

  @override
  void dispose() {
    _loggedEvents.close();
    super.dispose();
  }

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
      AppLogger.error(
        'LibraryController',
        'Loading the shelf failed.',
        error: error,
      );
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
  ///
  /// [loggedAt], when given, backdates the reading event this logs (and
  /// so the streaks day it lands on) — never the shelf write itself,
  /// which always reflects when the command actually ran.
  Future<LibraryActionResult> startBook(
    String title, {
    DateTime? loggedAt,
  }) async {
    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

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
      _logEvent(ReadingEventType.start, book.title, occurredAt: loggedAt);
      return LibraryActionResult.success('Started "${book.title}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `update <book> <page>` — validate the page, apply it locally so the
  /// shelf redraws immediately, then persist. If the write fails the
  /// optimistic change is rolled back, so what's on screen always
  /// matches what's stored.
  Future<LibraryActionResult> updateProgress(
    String title,
    int page, {
    DateTime? loggedAt,
  }) async {
    final entry = _findByTitle(title);
    if (entry == null) {
      return LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );
    }

    final validation = _validatePage(page, entry);
    if (validation != null) return LibraryActionResult.failure(validation);

    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

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
      // Reaching the last page via `update` still reads as a finish on
      // the streaks page — the closed circle it earns there matches the
      // "Finished ..." pill this same call just showed.
      loggedAs: finished ? ReadingEventType.finish : ReadingEventType.update,
      title: entry.book.title,
      occurredAt: loggedAt,
    );
  }

  /// `finish <book>` — mark complete and jump the page to the end when
  /// the total is known, so the finished card doesn't show a half-full
  /// bar next to a "finished" label.
  Future<LibraryActionResult> finishBook(
    String title, {
    DateTime? loggedAt,
  }) async {
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

    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

    return _persist(
      entry,
      entry.progress.copyWith(
        currentPage: entry.pageCount ?? entry.currentPage,
        status: ReadingStatus.finished,
        // Reflects the backdated day when one was given, so the book's
        // own record agrees with the streak entry it produced instead
        // of showing whenever this command happened to run.
        finishedAt: (loggedAt ?? DateTime.now()).toUtc(),
      ),
      successMessage: 'Finished "${entry.book.title}"',
      loggedAs: ReadingEventType.finish,
      title: entry.book.title,
      occurredAt: loggedAt,
    );
  }

  /// `rate <book> <stars>` — only allowed once the book is finished, so
  /// a rating always reflects a book actually read rather than a
  /// prediction. Optimistic like the other commands: the star shows
  /// immediately and rolls back if the write fails.
  ///
  /// Uses [UserBookRepository.rate] rather than [_persist] — that helper
  /// writes progress/status through [UserBookRepository.saveProgress],
  /// which has no `rating` column in its update and would silently drop
  /// this write.
  Future<LibraryActionResult> rateBook(String title, double rating) async {
    final entry = _findByTitle(title);
    if (entry == null) {
      return LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );
    }
    if (!entry.isFinished) {
      return LibraryActionResult.failure(
        'Finish "${entry.book.title}" before rating it.',
      );
    }

    // Half-star granularity — rounded here (not just in the parser) so
    // the rule holds no matter who calls rateBook, and the star row
    // never has to render a value finer than it can actually display.
    final rounded = (rating * 2).round() / 2;
    if (rounded <= 0 || rounded > 5) {
      return const LibraryActionResult.failure(
        'Ratings are between 0.5 and 5 stars.',
      );
    }

    final previous = entry;
    _upsertLocal(
      entry.copyWith(progress: entry.progress.copyWith(rating: rounded)),
    );
    notifyListeners();

    try {
      final saved = await userBooks.rate(
        userBookId: entry.progress.id,
        rating: rounded,
      );
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      _logEvent(ReadingEventType.rate, entry.book.title);
      return LibraryActionResult.success(
        '"${entry.book.title}" — ${_formatStars(rounded)}★',
      );
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Drops a trailing ".0" ("5★" rather than "5.0★") but keeps a real
  /// half ("4.5★") — mirrors `LogCommandParser`'s own formatting so the
  /// optimistic pill message and this result never disagree.
  static String _formatStars(double rating) {
    return rating == rating.roundToDouble()
        ? rating.toInt().toString()
        : rating.toStringAsFixed(1);
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
      _logEvent(ReadingEventType.delete, entry.book.title);
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
    required ReadingEventType loggedAs,
    required String title,
    DateTime? occurredAt,
  }) async {
    final previous = entry;
    _upsertLocal(entry.copyWith(progress: updated));
    notifyListeners();

    try {
      final saved = await userBooks.saveProgress(
        userBookId: updated.id,
        currentPage: updated.currentPage,
        finished: updated.isFinished,
        // Ignored server-side unless `updated.isFinished` — see
        // `UserBookRepository.saveProgress`'s own doc comment.
        finishedAt: occurredAt,
      );
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      _logEvent(loggedAs, title, occurredAt: occurredAt);
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

  /// A backdated command's date can't be in the future — "I started
  /// Dune tomorrow" isn't a reading event that happened yet. Compared
  /// in local time: [loggedAt] is a plain calendar date (local midnight
  /// on that day, see `ParsedLogCommand.date`), so comparing it against
  /// UTC "now" would reject today itself for any reader west of UTC.
  String? _validateLoggedAt(DateTime? loggedAt) {
    if (loggedAt == null) return null;
    if (loggedAt.isAfter(DateTime.now())) {
      return "That date hasn't happened yet.";
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
