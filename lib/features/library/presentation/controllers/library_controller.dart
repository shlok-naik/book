import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/formatting/numbers.dart';
import '../../data/book_details_repository.dart';
import '../../data/book_notes_repository.dart';
import '../../data/book_series_repository.dart';
import '../../data/collections_repository.dart';
import '../../data/reading_event_repository.dart';
import '../../data/user_book_repository.dart';
import '../../domain/book.dart';
import '../../domain/book_details_service.dart';
import '../../domain/book_edition.dart';
import '../../domain/book_lookup_service.dart';
import '../../domain/book_note.dart';
import '../../domain/book_series.dart';
import '../../domain/collections.dart';
import '../../domain/library_book.dart';
import '../../domain/library_exception.dart';
import '../../domain/reading_event.dart';
import '../../domain/shelf_rules.dart';
import '../../domain/user_book.dart';

/// Outcome of a library command, in a form the log page can show.
/// Commands never throw at the UI — failures come back as a
/// [LibraryActionResult] with `success == false` and a friendly message.
class LibraryActionResult {
  const LibraryActionResult.success([this.message, this.addedToLibrary = false])
    : success = true,
      cancelled = false;
  const LibraryActionResult.failure(this.message)
    : success = false,
      cancelled = false,
      addedToLibrary = false;

  /// The reader backed out before anything was attempted — not a failure,
  /// so it gets no rejection haptic or shake.
  const LibraryActionResult.cancelled(this.message)
    : success = false,
      cancelled = true,
      addedToLibrary = false;

  final bool success;
  final bool cancelled;
  final String? message;

  /// The command's book wasn't on the shelf, so it was added first (see
  /// `LibraryController._onShelfOrAdd`). The add tab shows [message] in
  /// that case rather than the parser's own wording, which can't know the
  /// book was added.
  final bool addedToLibrary;
}

/// Holds the reader's shelf and applies the log-page commands to it.
///
/// The UI observes this ([ChangeNotifier]) and never talks to Supabase or
/// Google Books itself — all I/O goes through the injected service and
/// repository, which is what makes the whole feature mockable in tests.
///
/// It is the single mutation point for shelf state — status, progress,
/// rating, owned edition and manual order — whether the change comes from
/// a typed command, a drag (or keyboard/screen-reader move) on the library
/// page, or the book detail/editions pages.
/// Every shelf change in particular goes through one private path,
/// [_changeShelf] (or [moveBook], which adds a reorder to it), so the
/// side effects [ShelfRules.enterShelf] defines apply identically everywhere.
///
/// ## Collections: make first, apply after
///
/// It also owns the reader's standalone collections — custom [shelves],
/// [tags] and [mySeries] — and is the one place they are created:
/// [makeShelf], [makeTag] and [makeSeries]. The `make shelf`/`make tag`/
/// `make series` commands and the library page's "+" panel both call these,
/// so there is exactly one validation and one write per kind. Applying a
/// collection to a book ([moveToShelf], [addTag], [addToSeries]) only ever
/// *looks one up*; a name that doesn't exist yet is a failure telling the
/// reader which `make` command to run, never an implicit creation.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.lookup,
    required this.userBooks,
    ReadingEventRepository? events,
    BookNotesRepository? notes,
    BookDetailsService? details,
    BookSeriesRepository? series,
    CollectionsRepository? collections,
  }) : events = events ?? ReadingEventRepository(),
       notes = notes ?? BookNotesRepository(),
       series = series ?? BookSeriesRepository(),
       collections = collections ?? CollectionsRepository(),
       details =
           details ??
           BookDetailsService(
             cache: BookDetailsRepository(),
             googleBooks: lookup.googleBooks,
           );

  /// Cache-first title resolution (Supabase → Google Books → write-back).
  final BookLookupService lookup;

  /// Progress reads/writes.
  final UserBookRepository userBooks;

  /// Per-command history for the streaks page. Optional at construction
  /// (defaults to a real repository) so existing callers/tests that only
  /// care about shelf state don't have to know this exists.
  final ReadingEventRepository events;

  /// Tags and comments on shelf rows — written here for the `add tag` /
  /// `add comment` commands, and read/written by the book detail page's
  /// own controller. Optional at construction for the same reason
  /// [events] is.
  final BookNotesRepository notes;

  /// Cache-first extended info and editions for the book detail page.
  /// Held here only so the composition root stays the one place it is
  /// built; the detail page reaches it through `LibraryScope` rather than
  /// constructing its own. Defaults to one sharing [lookup]'s Google Books
  /// client.
  final BookDetailsService details;

  /// The reader's own series list, private to them — `make series` and
  /// `add series` write it, the series page reads it.
  final BookSeriesRepository series;

  /// The reader's own custom shelves and tags — [makeShelf]/[makeTag] write
  /// them, [load] reads them.
  final CollectionsRepository collections;

  final _loggedEvents = StreamController<ReadingEvent>.broadcast();

  /// Every [ReadingEvent] that has actually been persisted, in the order
  /// it landed. The streaks feature listens to this to update its own
  /// state directly — this stream carries only the one thing that
  /// changed, unlike this class's own [notifyListeners] (a "the shelf
  /// changed somehow" signal that would otherwise force a full-year
  /// Supabase refetch on every single shelf command).
  Stream<ReadingEvent> get loggedEvents => _loggedEvents.stream;

  final _clearedTitles = StreamController<String>.broadcast();

  /// A book title whose whole journal history was just erased — see
  /// [_clearJournal]. The streaks feature listens to this the same way
  /// it listens to [loggedEvents], so a deleted book's old "started"/
  /// "read up to page..." lines disappear from an already-open journal
  /// without a reload.
  Stream<String> get clearedTitles => _clearedTitles.stream;

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
  void _logEvent(
    ReadingEventType type,
    String title, {
    DateTime? occurredAt,
    double? value,
  }) {
    final at = (occurredAt ?? DateTime.now()).toUtc();
    final event = ReadingEvent(
      type: type,
      occurredAt: at,
      title: title,
      value: value,
    );
    reportingFailure(
      events
          .log(type, title: title, occurredAt: at, value: value)
          .then((_) => _emit(_loggedEvents, event)),
      source: 'LibraryController',
      message: 'Could not record a "${type.wireValue}" reading event.',
    );
  }

  /// Erases [title]'s whole journal history — `delete <book>` removing
  /// the book from the shelf takes its "started"/"finished"/etc. lines
  /// with it, rather than leaving a trail for a book that's gone.
  /// Fire-and-forget for the same reason [_logEvent] is: a failure here
  /// must never surface as a failed `delete` command, since the shelf
  /// write it followed has already succeeded.
  void _clearJournal(String title) {
    reportingFailure(
      events.deleteForTitle(title).then((_) => _emit(_clearedTitles, title)),
      source: 'LibraryController',
      message: 'Could not clear the journal for "$title".',
    );
  }

  final _resets = StreamController<void>.broadcast();

  /// Fires after the whole shelf was replaced from outside a single
  /// command — a Goodreads import, or an account's library swapped when an
  /// email is linked. Anything holding its own derived copy of the shelf's
  /// history (the streak journal, the add tab's week row) reloads on it.
  Stream<void> get resets => _resets.stream;

  final _tagsChanged = StreamController<void>.broadcast();

  /// Fires after a tag was applied to or removed from a book — tags live
  /// outside the shelf rows [notifyListeners] covers, so anything counting
  /// them (the stats page's tags section) listens here instead of
  /// refetching on every shelf change.
  Stream<void> get tagsChanged => _tagsChanged.stream;

  /// Announces a tag write made outside this controller — the book page's
  /// `BookDetailController` applies and removes tags on its own.
  void notifyTagsChanged() => _emit(_tagsChanged, null);

  /// Reloads the shelf and tells [resets] listeners to reload theirs.
  ///
  /// Always a *fresh* load: a load already in flight started before the
  /// library was replaced and would answer with the old shelf, so it is
  /// waited out first rather than joined.
  Future<void> reset() async {
    _books = const [];
    notifyListeners();
    await _inFlightLoad;
    await load();
    _emit(_resets, null);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _loggedEvents.close();
    _clearedTitles.close();
    _resets.close();
    _tagsChanged.close();
    super.dispose();
  }

  /// Adds to [controller] unless this controller was disposed — every
  /// broadcast here can fire from a write that outlives the app root.
  static void _emit<T>(StreamController<T> controller, T value) {
    if (!controller.isClosed) controller.add(value);
  }

  /// The shelf in its natural order — most recently updated first, as
  /// `UserBookRepository.fetchLibrary` returns it. Section getters sort
  /// on top of this; [currentlyReading] and title matching rely on it.
  ///
  /// Never mutated in place — every change assigns a new list. The
  /// memoized views below ([books], [shelfSection]) rely on that: they are
  /// keyed on this list's identity.
  List<LibraryBook> _books = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;

  List<LibraryBook>? _booksViewSource;
  List<LibraryBook> _booksView = const [];

  /// Every book on the shelf, most recently updated first.
  ///
  /// A read-only view rather than a copy, and the *same* view until the
  /// shelf changes — so a caller can cheaply tell "nothing changed" by
  /// identity (see `ReadingStats.forShelf`).
  List<LibraryBook> get books {
    if (!identical(_booksViewSource, _books)) {
      _booksViewSource = _books;
      _booksView = UnmodifiableListView(_books);
    }
    return _booksView;
  }

  /// Every section's display order, computed once per shelf/shelves change
  /// rather than filtered and sorted again on every access — the library
  /// page asks for each section on every rebuild.
  Map<ShelfRef, List<LibraryBook>>? _sections;
  List<LibraryBook>? _sectionsBooks;
  List<Shelf>? _sectionsShelves;

  List<Shelf> _shelves = const [];
  List<ReaderTag> _tags = const [];
  List<BookSeries> _mySeries = const [];
  DateTime? _importedAt;

  /// When the reader last imported a library (Goodreads), or null — the
  /// stats page's baseline: imported books stay out of its monthly charts,
  /// and pace counts from here. Loaded with the shelf; a failed fetch keeps
  /// the last known value.
  DateTime? get importedAt => _importedAt;

  /// The reader's custom shelves, oldest first — shown after the four
  /// built-in shelves on the library page.
  List<Shelf> get shelves => List.unmodifiable(_shelves);

  /// The reader's tags, alphabetically.
  List<ReaderTag> get tags => List.unmodifiable(_tags);

  /// The series on the reader's own list, alphabetically.
  List<BookSeries> get mySeries => List.unmodifiable(_mySeries);

  /// Books in the "reading" section, in shelf order — see [section]. A
  /// reading book on a custom shelf isn't in it; use [books] and
  /// `LibraryBook.isReading` to count every book being read.
  List<LibraryBook> get inProgress => section(ReadingStatus.reading);

  /// `move <book> tbr` — queued books, rendered in their own section.
  List<LibraryBook> get toBeRead => section(ReadingStatus.toBeRead);

  /// Completed books — rendered in their own section on the same page.
  List<LibraryBook> get finished => section(ReadingStatus.finished);

  /// `move <book> dnf` — dropped books, rendered in their own section.
  List<LibraryBook> get didNotFinish => section(ReadingStatus.dnf);

  /// One built-in library-page section in display order — see
  /// [shelfSection].
  List<LibraryBook> section(ReadingStatus status) =>
      shelfSection(StatusShelfRef(status));

  /// Any library-page section, built-in or custom, in display order: books
  /// never placed by hand first (most recently updated first), then the
  /// reader's own drag-and-drop order — see [ShelfRules.sortSection].
  List<LibraryBook> shelfSection(ShelfRef shelf) =>
      _sectionMap()[shelf] ?? const [];

  Map<ShelfRef, List<LibraryBook>> _sectionMap() {
    final cached = _sections;
    if (cached != null &&
        identical(_sectionsBooks, _books) &&
        identical(_sectionsShelves, _shelves)) {
      return cached;
    }
    final grouped = <ShelfRef, List<LibraryBook>>{};
    for (final entry in _books) {
      (grouped[placementOf(entry)] ??= []).add(entry);
    }
    _sectionsBooks = _books;
    _sectionsShelves = _shelves;
    return _sections = {
      for (final MapEntry(:key, :value) in grouped.entries)
        key: List.unmodifiable(ShelfRules.sortSection(value)),
    };
  }

  /// The section [entry] is shown in. A `shelf_id` naming a shelf that
  /// isn't loaded (its fetch failed) falls back to the status section,
  /// so a failed shelves load can never make a book vanish from the page.
  ShelfRef placementOf(LibraryBook entry) {
    final shelfId = entry.shelfId;
    if (shelfId != null && _shelfById(shelfId) != null) {
      return CustomShelfRef(shelfId);
    }
    return StatusShelfRef(entry.status);
  }

  Shelf? _shelfById(String id) {
    for (final shelf in _shelves) {
      if (shelf.id == id) return shelf;
    }
    return null;
  }

  /// The display name of any shelf — "to read", or a custom shelf's own.
  String shelfName(ShelfRef shelf) => switch (shelf) {
    StatusShelfRef(:final status) => switch (status) {
      ReadingStatus.reading => 'reading',
      ReadingStatus.toBeRead => 'to read',
      ReadingStatus.finished => 'finished',
      ReadingStatus.dnf => 'did not finish',
    },
    CustomShelfRef(:final shelfId) => _shelfById(shelfId)?.name ?? 'that shelf',
  };

  /// The reading book the reader touched most recently — what the add
  /// tab's "currently reading" row shows. Deliberately *not*
  /// `inProgress.first`: that list is in the reader's manual shelf order,
  /// and dragging a book to the top of "reading" is arranging the shelf,
  /// not reading it.
  LibraryBook? get currentlyReading {
    for (final entry in _books) {
      if (entry.isReading) return entry;
    }
    return null;
  }

  /// The live shelf row for a `user_books` id, or null once it is gone.
  /// The detail page holds an id, not a [LibraryBook] snapshot, and reads
  /// the row back through this on every rebuild so it always shows what
  /// the shelf currently says.
  LibraryBook? findById(String userBookId) {
    for (final entry in _books) {
      if (entry.id == userBookId) return entry;
    }
    return null;
  }

  /// The shelf book a typed [title] refers to, by the same rule every
  /// title-taking command uses — so a confirmation can name the exact book
  /// the command is about to act on. Null when nothing matches.
  LibraryBook? match(String title) => _findByTitle(title);

  bool get isLoading => _isLoading;

  /// Set when the last *load* failed, so the page can show a retry.
  /// Command failures are reported through [LibraryActionResult] instead.
  String? get errorMessage => _errorMessage;

  bool get isEmpty => _books.isEmpty;

  /// Whether a load has finished at least once (successfully or not) — lets
  /// a page that mounts later skip a reload of a shelf already on screen.
  bool get hasLoaded => _hasLoaded;

  Future<void>? _inFlightLoad;

  /// (Re)loads the shelf from Supabase. Safe to call repeatedly: a call
  /// while one is in flight *joins* it — the returned future completes when
  /// that load does — so a caller that awaits this (pull-to-refresh, the
  /// CSV export, a sync) always sees the loaded shelf, never a half-started
  /// one.
  Future<void> load() =>
      _inFlightLoad ??= _load().whenComplete(() => _inFlightLoad = null);

  Future<void> _load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Collections load alongside the shelf, and each degrades on its own
      // (see [_loadCollections], which never throws) — a failed tags fetch
      // must not blank the shelf. The shelf fetch is awaited first so its
      // failure is caught here rather than escaping as an unawaited error.
      final collectionsLoaded = _loadCollections();
      _books = await userBooks.fetchLibrary();
      await collectionsLoaded;
      _errorMessage = null;
    } on LibraryException catch (error) {
      _errorMessage = error.message;
      AppLogger.error(
        'LibraryController',
        'Loading the shelf failed.',
        error: error,
      );
    } on Object catch (error, stackTrace) {
      // Callers fire this without awaiting (startup, resume, a sync); an
      // unexpected parse error must still read as a failed load with a
      // retry, not escape as an unhandled error behind a spinner.
      _errorMessage = "We couldn't load your library.";
      AppLogger.error(
        'LibraryController',
        'Loading the shelf failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// Refreshes [shelves], [tags] and [mySeries]. A fetch that fails keeps
  /// what was already loaded and is only logged: these lists feed lookups
  /// and the "+" panel, and a stale list is better than an empty one.
  Future<void> _loadCollections() async {
    Future<void> attempt<T>(
      String what,
      Future<List<T>> Function() fetch,
      void Function(List<T>) apply,
    ) async {
      try {
        apply(await fetch());
      } on LibraryException catch (error) {
        AppLogger.info('LibraryController', 'Could not load $what: $error');
      }
    }

    Future<void> importBaseline() async {
      try {
        _importedAt = await userBooks.fetchImportedAt();
      } on LibraryException catch (error) {
        AppLogger.info(
          'LibraryController',
          'Could not load import date: $error',
        );
      }
    }

    await Future.wait([
      importBaseline(),
      attempt<Shelf>('shelves', collections.fetchShelves, (v) => _shelves = v),
      attempt<ReaderTag>('tags', collections.fetchTags, (v) => _tags = v),
      attempt<BookSeries>('series', series.fetchMySeries, (v) => _mySeries = v),
    ]);
  }

  // ------------------------------------------------------------ collections

  /// Free plan: no custom shelves at all. `isPro` is read at the call
  /// site ([PlanController.isPro], the same debug-aware flag `HomePage`
  /// checks before `remember`/`recommend`) rather than cached here, so
  /// this controller stays purchase-agnostic — it just does the counting.
  bool canMakeShelf(bool isPro) => isPro;

  /// Free plan: up to 2 tags total.
  bool canMakeTag(bool isPro) => isPro || _tags.length < 2;

  /// Free plan: up to 1 series total.
  bool canMakeSeries(bool isPro) => isPro || _mySeries.isEmpty;

  /// `make shelf <name>` and the "+" panel's shelves tab — the one way a
  /// custom shelf comes into existence. Refuses a name the reader already
  /// has (built-in names included) before any I/O. [isPro] gates whether a
  /// custom shelf can be made at all — see [canMakeShelf].
  Future<LibraryActionResult> makeShelf(
    String name, {
    required bool isPro,
  }) async {
    if (!canMakeShelf(isPro)) {
      return const LibraryActionResult.failure(
        'Upgrade to cactus pro to make custom shelves.',
      );
    }
    try {
      final clean = CollectionNames.validateShelf(name);
      if (findShelf(clean) != null) {
        return LibraryActionResult.failure(
          'You already have a shelf "$clean".',
        );
      }
      final shelf = await collections.createShelf(clean);
      _shelves = [..._shelves, shelf];
      notifyListeners();
      return LibraryActionResult.success('Made shelf "${shelf.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `make tag <tag>` and the "+" panel's tags tab — the one way a tag
  /// comes into existence. Free plan caps at 2 tags total — see
  /// [canMakeTag].
  Future<LibraryActionResult> makeTag(
    String name, {
    required bool isPro,
  }) async {
    if (!canMakeTag(isPro)) {
      return const LibraryActionResult.failure(
        'Upgrade to cactus pro for unlimited tags — free includes 2.',
      );
    }
    try {
      final clean = CollectionNames.validateTag(name);
      if (findTag(clean) != null) {
        return LibraryActionResult.failure('You already have a tag "$clean".');
      }
      final tag = await collections.createTag(clean);
      _tags = [..._tags, tag]..sort(_byName((t) => t.name));
      notifyListeners();
      return LibraryActionResult.success('Made tag "${tag.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `make series <name>` and the "+" panel's series tab — the one way a
  /// series comes into existence. Private to this reader, like a shelf or a
  /// tag — refuses a name they already have before any I/O. Free plan caps
  /// at 1 series total — see [canMakeSeries].
  Future<LibraryActionResult> makeSeries(
    String name, {
    required bool isPro,
  }) async {
    if (!canMakeSeries(isPro)) {
      return const LibraryActionResult.failure(
        'Upgrade to cactus pro for unlimited series — free includes 1.',
      );
    }
    try {
      final clean = CollectionNames.validateSeries(name);
      if (findSeries(clean) case final existing?) {
        return LibraryActionResult.failure(
          'You already have a series "${existing.name}".',
        );
      }
      final made = await series.makeSeries(clean);
      _addSeriesLocal(made);
      return LibraryActionResult.success('Made series "${made.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  void _addSeriesLocal(BookSeries made) {
    _mySeries = [..._mySeries, made]..sort(_byName((s) => s.name));
    notifyListeners();
  }

  static int Function(T, T) _byName<T>(String Function(T) name) =>
      (a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase());

  /// The shelf [name] refers to — a built-in one by any of its names
  /// ("tbr", "to read"…), or a custom one by its own name, ignoring case and
  /// spacing. Null when no shelf has that name.
  ShelfRef? findShelf(String name) {
    final status = CollectionNames.builtInShelf(name);
    if (status != null) return StatusShelfRef(status);
    final key = CollectionNames.key(name);
    for (final shelf in _shelves) {
      if (CollectionNames.key(shelf.name) == key) {
        return CustomShelfRef(shelf.id);
      }
    }
    return null;
  }

  /// The reader's tag called [name], ignoring case and spacing, or null.
  ReaderTag? findTag(String name) {
    final key = CollectionNames.key(name);
    for (final tag in _tags) {
      if (CollectionNames.key(tag.name) == key) return tag;
    }
    return null;
  }

  /// The series on the reader's list called [name], or null.
  BookSeries? findSeries(String name) {
    for (final entry in _mySeries) {
      if (entry.matches(name)) return entry;
    }
    return null;
  }

  // ------------------------------------------------------------------ books

  /// `start <book>` — resolve the title cache-first, then put it on the
  /// shelf at page 0.
  ///
  /// Never creates a duplicate shelf entry — starting a book already on
  /// the shelf leaves its progress untouched — but that repeat is
  /// reported as a *failure*, not a success: nothing changed, so it
  /// shouldn't look like it did.
  ///
  /// [loggedAt], when given, backdates the reading event this logs (and
  /// so the streaks day it lands on) and the book's start date — the one
  /// the book page shows and lets the reader edit. The shelf's own
  /// ordering still reflects when the command actually ran.
  ///
  /// A book already on the shelf *to read* is started — moved to reading,
  /// exactly as `move <book> reading` would, start date stamped — rather
  /// than refused: "start" is what a reader says when they pick up a book
  /// they had queued.
  Future<LibraryActionResult> startBook(String title, {DateTime? loggedAt}) =>
      _start(() => lookup.findOrFetch(title), loggedAt: loggedAt);

  /// `start isbn` once the camera has scanned a barcode — same shelf
  /// write as [startBook], resolving [isbn] cache-first through
  /// [BookLookupService.findOrFetchByIsbn] instead of by title. An ISBN
  /// names one specific edition rather than a title that could match
  /// several, so there's no "best match" guesswork here the way there is
  /// for a typed title.
  Future<LibraryActionResult> startBookByIsbn(
    String isbn, {
    DateTime? loggedAt,
  }) => _start(() => lookup.findOrFetchByIsbn(isbn), loggedAt: loggedAt);

  /// The shared body of [startBook] and [startBookByIsbn] — they differ
  /// only in how the book is resolved.
  Future<LibraryActionResult> _start(
    Future<Book> Function() resolve, {
    DateTime? loggedAt,
  }) async {
    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

    try {
      final book = await resolve();
      final existing = _findByBookId(book.id);
      if (existing != null) {
        if (existing.status == ReadingStatus.toBeRead) {
          return _changeShelf(
            existing,
            const StatusShelfRef(ReadingStatus.reading),
            at: loggedAt,
          );
        }
        // Already on the shelf locally: nothing to write, so no round trip
        // just to have the server say the same thing.
        return LibraryActionResult.failure(
          '"${existing.book.title}" is already on your shelf.',
        );
      }
      final started = await userBooks.start(book.id, startedAt: loggedAt);
      _upsertLocal(LibraryBook(book: book, progress: started.progress));
      notifyListeners();
      _warmEditions(book);
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

  /// Warms the shared `book_editions` cache for [book] in the background,
  /// right after it lands on the shelf — so opening its editions page
  /// later is a cache hit instead of a live Google Books search, for this
  /// reader or the next one to reach the same book. A no-op once the book
  /// already has cached editions. Fire-and-forget: a warm that fails costs
  /// nothing beyond a slower first open, and must never affect the shelf
  /// command that triggered it.
  void _warmEditions(Book book) {
    if (book.hasCachedEditions) return;
    reportingFailure(
      details.editionsFor(book).then((_) {}),
      source: 'LibraryController',
      message: 'Could not warm the edition cache for "${book.title}".',
    );
  }

  /// `move <book> <shelf>` — puts [title] on the shelf called [shelfName]:
  /// one of the built-in shelves (see [CollectionNames.builtInShelves]) or
  /// a custom shelf the reader already made.
  ///
  /// A shelf that doesn't exist is refused, naming the `make shelf` command
  /// that would create it — `move` never makes a shelf on the reader's
  /// behalf, so a typo can't quietly become a new shelf.
  ///
  /// A book *already* on the shelf is moved through [_changeShelf] — the
  /// same move a drag on the library page makes, so a command and a drag
  /// can never disagree about what "moved to finished" means. A book not on
  /// the shelf yet is resolved cache-first and added straight there: at that
  /// status with the progress it implies (see [ShelfRules.enter]), or, for a
  /// custom shelf, as a to-read book placed on it. Only a book already on
  /// that exact shelf has nothing to change, and reports failure.
  Future<LibraryActionResult> moveToShelf(
    String title,
    String shelfName,
  ) async {
    final target = findShelf(shelfName);
    if (target == null) return _noSuchShelf(shelfName);

    try {
      // Resolved through the catalogue first, not a fuzzy shelf match:
      // "move Dune tbr" must add Dune, not move a "Dune Messiah" that
      // happens to be on the shelf already.
      final book = await lookup.findOrFetch(title);
      final existing = _findByBookId(book.id);
      if (existing != null) return _changeShelf(existing, target);

      final status = switch (target) {
        StatusShelfRef(:final status) => status,
        CustomShelfRef() => ReadingStatus.toBeRead,
      };
      final page = status == ReadingStatus.finished ? book.pageCount ?? 0 : 0;
      final added = await userBooks.addWithStatus(
        book.id,
        status,
        currentPage: page,
        shelfId: switch (target) {
          CustomShelfRef(:final shelfId) => shelfId,
          StatusShelfRef() => null,
        },
      );
      final entry = LibraryBook(book: book, progress: added.progress);
      _upsertLocal(entry);
      notifyListeners();
      _warmEditions(book);
      if (added.alreadyExists) {
        // Rare race: the row appeared between the local lookup above and
        // this write landing, and came back at whatever shelf it was
        // already on. Finish the move the same way as a local hit.
        return _changeShelf(entry, target);
      }
      _logEvent(_eventForShelf(status), book.title);
      return LibraryActionResult.success(_addedMessage(book.title, target));
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `move <book> <shelf>` typed without quotes around the shelf — "move
  /// dune summer reads" — where only the shelves themselves can say where
  /// the title ends. Split by [splitTrailingShelf], then [moveToShelf].
  Future<LibraryActionResult> moveToShelfUnsplit(String argument) {
    final split = splitTrailingShelf(argument);
    if (split == null) {
      final words = argument.trim().split(RegExp(r'\s+'));
      return Future.value(_noSuchShelf(words.last));
    }
    return moveToShelf(split.title, split.shelfName);
  }

  /// Splits "dune messiah summer reads" into a book title and the name of a
  /// shelf that exists. The *longest* trailing run of words naming a shelf
  /// wins, so a custom "summer reading" beats the built-in "reading". At
  /// least one word is always left for the title. Null when no trailing run
  /// names a shelf.
  ({String title, String shelfName})? splitTrailingShelf(String words) {
    final tokens = words.trim().split(RegExp(r'\s+'));
    for (var start = 1; start < tokens.length; start++) {
      final candidate = tokens.sublist(start).join(' ');
      if (findShelf(candidate) != null) {
        return (
          title: tokens.sublist(0, start).join(' '),
          shelfName: candidate,
        );
      }
    }
    return null;
  }

  static LibraryActionResult _noSuchShelf(String name) {
    final clean = CollectionNames.clean(name);
    return LibraryActionResult.failure(
      'No shelf called "$clean" — make it first with make shelf $clean.',
    );
  }

  /// Drag-and-drop on the library page: moves [userBookId] to the [shelf]
  /// section — built-in or custom — and drops it at [index] within that
  /// section's current display order.
  ///
  /// Within the same section this is a pure reorder — progress is
  /// untouched and no reading event is logged. Into a different section it
  /// is a shelf change first, with [ShelfRules.enterShelf]'s side effects
  /// (to read/reading → page 0, finished → 100%, a custom shelf → progress
  /// kept), then a reorder.
  ///
  /// Optimistic, like every other mutation here: the whole shelf is
  /// snapshotted, the move applied locally and listeners notified, then
  /// the writes run; if any fails, the snapshot goes back. Rolling back
  /// the *whole* shelf rather than one row matters because a reorder
  /// renumbers every book in the target section.
  ///
  /// A drop back onto the exact spot it started from is a no-op and
  /// returns a failure with a null message — nothing happened, so there
  /// is nothing to confirm and nothing to complain about.
  Future<LibraryActionResult> moveBook(
    String userBookId,
    ShelfRef shelf,
    int index,
  ) async {
    final entry = findById(userBookId);
    if (entry == null) return _missingById;

    final target = shelfSection(shelf);
    final order = ShelfRules.orderAfterDrop(target, entry.id, index);
    final isMove = placementOf(entry) != shelf;
    if (!isMove && _sameOrder(order, [for (final e in target) e.id])) {
      return const LibraryActionResult.failure(null);
    }

    final snapshot = _books;
    final moved = ShelfRules.enterShelf(entry, shelf);
    final statusChanged = moved.status != entry.status;
    _upsertLocal(entry.copyWith(progress: moved));
    _applyOrderLocally(order);
    notifyListeners();

    UserBook? savedMove;
    try {
      if (isMove) {
        final saved = savedMove = await userBooks.changeShelf(moved);
        // The server cleared the row's position on the status change;
        // keep the one just assigned locally, which the next write stores.
        final placed = findById(entry.id)?.progress.shelfPosition;
        _upsertLocal(
          entry.copyWith(progress: saved.copyWith(shelfPosition: placed)),
        );
      }
      await userBooks.saveShelfOrder(order);
      notifyListeners();
      if (statusChanged) {
        _logEvent(_eventForShelf(moved.status), entry.book.title);
      }
      return LibraryActionResult.success(
        isMove ? _movedMessage(entry.book.title, shelf) : null,
      );
    } on LibraryException catch (error) {
      _books = snapshot;
      if (savedMove == null) {
        notifyListeners();
        return LibraryActionResult.failure(error.message);
      }
      // The shelf change itself landed; only the order write didn't. Rolling
      // the book back would show it on a shelf the server no longer has it
      // on, so keep the saved move — unplaced, as the server left it — and
      // put only the other books' positions back.
      _upsertLocal(
        entry.copyWith(progress: savedMove.copyWith(clearShelfPosition: true)),
      );
      notifyListeners();
      if (statusChanged) {
        _logEvent(_eventForShelf(moved.status), entry.book.title);
      }
      return LibraryActionResult.failure(
        '${_movedMessage(entry.book.title, shelf)}, but its spot on the '
        "shelf didn't save.",
      );
    }
  }

  /// The one write path for "this book is now on a different shelf",
  /// used by [moveToShelf] ([moveBook] does the same thing plus a reorder).
  /// Optimistic with rollback. Journals the move only when it changed the
  /// book's reading status — putting a book on a custom shelf isn't a
  /// reading moment.
  Future<LibraryActionResult> _changeShelf(
    LibraryBook entry,
    ShelfRef shelf, {
    DateTime? at,
  }) async {
    if (placementOf(entry) == shelf) {
      return LibraryActionResult.failure(
        '"${entry.book.title}" is already ${_shelfPhrase(shelf)}.',
      );
    }

    final previous = entry;
    final moved = ShelfRules.enterShelf(entry, shelf, at: at);
    _upsertLocal(entry.copyWith(progress: moved));
    notifyListeners();

    try {
      final saved = await userBooks.changeShelf(moved);
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      if (saved.status != previous.status) {
        _logEvent(
          _eventForShelf(saved.status),
          entry.book.title,
          occurredAt: at,
        );
      }
      return LibraryActionResult.success(
        _movedMessage(entry.book.title, shelf),
      );
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Which journal line a shelf change reads back as. Moving (back) into
  /// "reading" is starting the book; the other three already had one.
  static ReadingEventType _eventForShelf(ReadingStatus status) =>
      switch (status) {
        ReadingStatus.reading => ReadingEventType.start,
        ReadingStatus.toBeRead => ReadingEventType.addToBeRead,
        ReadingStatus.finished => ReadingEventType.finish,
        ReadingStatus.dnf => ReadingEventType.dnf,
      };

  String _shelfPhrase(ShelfRef shelf) => switch (shelf) {
    StatusShelfRef(status: ReadingStatus.reading) => 'being read',
    StatusShelfRef(status: ReadingStatus.toBeRead) => 'on your to-read shelf',
    StatusShelfRef(status: ReadingStatus.finished) => 'finished',
    StatusShelfRef(status: ReadingStatus.dnf) => 'marked as DNF',
    CustomShelfRef() => 'on ${shelfName(shelf)}',
  };

  String _addedMessage(String title, ShelfRef shelf) => switch (shelf) {
    StatusShelfRef(status: ReadingStatus.reading) => 'Started "$title"',
    StatusShelfRef(status: ReadingStatus.toBeRead) => 'Added "$title" to read',
    StatusShelfRef(status: ReadingStatus.finished) =>
      'Added "$title" as finished',
    StatusShelfRef(status: ReadingStatus.dnf) => 'Marked "$title" as DNF',
    CustomShelfRef() => 'Added "$title" to ${shelfName(shelf)}',
  };

  String _movedMessage(String title, ShelfRef shelf) => switch (shelf) {
    StatusShelfRef(status: ReadingStatus.reading) =>
      'Moved "$title" to reading',
    StatusShelfRef(status: ReadingStatus.toBeRead) => 'Moved "$title" to read',
    StatusShelfRef(status: ReadingStatus.finished) => 'Finished "$title"',
    StatusShelfRef(status: ReadingStatus.dnf) => 'Marked "$title" as DNF',
    CustomShelfRef() => 'Moved "$title" to ${shelfName(shelf)}',
  };

  /// Gives every book in [orderedIds] its index as its local shelf
  /// position — the local half of [UserBookRepository.saveShelfOrder].
  void _applyOrderLocally(List<String> orderedIds) {
    final positions = {
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i.toDouble(),
    };
    _books = [
      for (final entry in _books)
        if (positions[entry.id] case final position?)
          entry.copyWith(
            progress: entry.progress.copyWith(shelfPosition: position),
          )
        else
          entry,
    ];
  }

  static bool _sameOrder(List<String> a, List<String> b) => listEquals(a, b);

  /// `update <book> <page>` — validate the page, apply it locally so the
  /// shelf redraws immediately, then persist. If the write fails the
  /// optimistic change is rolled back, so what's on screen always
  /// matches what's stored.
  Future<LibraryActionResult> updateProgress(
    String title,
    int page, {
    DateTime? loggedAt,
  }) async {
    // On the shelf already: straight to the write, with no await before the
    // optimistic update — the page redraws in the same frame as the command.
    final existing = _findByTitle(title);
    if (existing != null) {
      return _updateEntryProgress(existing, page, loggedAt: loggedAt);
    }
    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);
    final resolved = await _onShelfOrAdd(
      title,
      ReadingStatus.reading,
      at: loggedAt,
      precheck: (candidate) => _validatePage(page, candidate),
    );
    final entry = resolved.entry;
    if (entry == null) return resolved.failure!;
    final result = await _updateEntryProgress(entry, page, loggedAt: loggedAt);
    return _markAdded(result, added: resolved.added);
  }

  /// The detail page's progress fields — [updateProgress] for a row
  /// already identified by id, so two books with similar titles can never
  /// be confused the way a typed title could.
  Future<LibraryActionResult> updateProgressById(String userBookId, int page) {
    final entry = findById(userBookId);
    if (entry == null) return Future.value(_missingById);
    return _updateEntryProgress(entry, page);
  }

  Future<LibraryActionResult> _updateEntryProgress(
    LibraryBook entry,
    int page, {
    DateTime? loggedAt,
  }) async {
    final validation = _validatePage(page, entry);
    if (validation != null) return LibraryActionResult.failure(validation);

    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

    // Reaching the last page completes the book; without a known page
    // count only an explicit `finish` can.
    final total = entry.pageCount;
    final finished = total != null && page >= total;
    final status = finished ? ReadingStatus.finished : ReadingStatus.reading;

    return _persist(
      entry,
      entry.progress.copyWith(
        currentPage: page,
        status: status,
        // An update that changes the shelf (a to-read book logged at page
        // 40, a book logged to its last page) lands at the top of its new
        // section, same as the server's trigger does. The page itself is
        // exactly what the reader typed — no [ShelfRules.enter] reset.
        clearShelfPosition: status != entry.status,
        clearFinishedAt: !finished,
      ),
      successMessage: finished
          ? 'Finished "${entry.book.title}"'
          : '"${entry.book.title}" — pg $page',
      // Reaching the last page via `update` still reads as a finish in
      // the journal — matches the "Finished ..." pill this same call
      // just showed, rather than "read up to page" the last page.
      loggedAs: finished ? ReadingEventType.finish : ReadingEventType.update,
      title: entry.book.title,
      occurredAt: loggedAt,
      value: finished ? null : page.toDouble(),
    );
  }

  /// `update <book> <percent>%` — same command as [updateProgress], just
  /// expressed as a percentage of the book's total length instead of a
  /// raw page number. Resolves to a page here (not in the parser, which
  /// has no access to a book's page count) through [pageForPercent], then
  /// takes the same write, validation, and rollback path.
  Future<LibraryActionResult> updateProgressByPercent(
    String title,
    double percent, {
    DateTime? loggedAt,
  }) async {
    final existing = _findByTitle(title);
    if (existing != null) {
      final resolved = pageForPercent(existing, percent);
      final page = resolved.page;
      if (page == null) return LibraryActionResult.failure(resolved.failure);
      return _updateEntryProgress(existing, page, loggedAt: loggedAt);
    }
    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);
    final onShelf = await _onShelfOrAdd(
      title,
      ReadingStatus.reading,
      at: loggedAt,
      // Checked before adding, so "update dune 50%" on a book whose length
      // Google doesn't know refuses cleanly instead of leaving it added.
      precheck: (candidate) => pageForPercent(candidate, percent).failure,
    );
    final entry = onShelf.entry;
    if (entry == null) return onShelf.failure!;
    final resolved = pageForPercent(entry, percent);
    final page = resolved.page;
    if (page == null) return LibraryActionResult.failure(resolved.failure);
    final result = await _updateEntryProgress(entry, page, loggedAt: loggedAt);
    return _markAdded(result, added: onShelf.added);
  }

  /// Converts [percent] of [entry]'s length to a page — the single rule
  /// both the `update <book> <percent>%` command and the detail page's
  /// percentage field use, so "74%" means the same page in both places.
  /// Returns a failure message instead (with a null page) when there is no
  /// page count to take a percentage of, or [percent] is out of range.
  static ({int? page, String? failure}) pageForPercent(
    LibraryBook entry,
    double percent,
  ) {
    if (!percent.isFinite || percent < 0 || percent > 100) {
      return (page: null, failure: 'A percentage has to be between 0 and 100.');
    }
    final total = entry.pageCount;
    if (total == null) {
      return (
        page: null,
        failure:
            'We don\'t know how many pages "${entry.book.title}" has — '
            'try a page number instead.',
      );
    }
    return (
      page: (percent / 100 * total).round().clamp(0, total),
      failure: null,
    );
  }

  /// `finish <book>` — mark complete and jump the page to the end when
  /// the total is known, so the finished card doesn't show a half-full
  /// bar next to a "finished" label.
  Future<LibraryActionResult> finishBook(
    String title, {
    DateTime? loggedAt,
  }) async {
    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

    // A hit resolves synchronously, so the optimistic finish below still
    // redraws in the same frame; only a miss goes through the async add.
    final onShelf = _findByTitle(title);
    final resolved = onShelf != null
        ? (entry: onShelf, added: false, failure: null)
        : await _onShelfOrAdd(title, ReadingStatus.finished, at: loggedAt);
    final entry = resolved.entry;
    if (entry == null) return resolved.failure!;
    if (resolved.added) {
      // Added straight onto the finished shelf — that *is* the finish.
      return LibraryActionResult.success(
        'Added "${entry.book.title}" as finished',
        true,
      );
    }
    if (entry.isFinished) {
      return LibraryActionResult.failure(
        '"${entry.book.title}" is already finished.',
      );
    }

    return _persist(
      entry,
      // The same progress a move to the finished shelf implies — the one
      // rule in [ShelfRules.enter] — with the finish backdated when a date
      // was given, so the book's own record agrees with the streak entry
      // it produced instead of showing whenever this command happened to
      // run.
      ShelfRules.enter(entry, ReadingStatus.finished, at: loggedAt),
      successMessage: 'Finished "${entry.book.title}"',
      loggedAs: ReadingEventType.finish,
      title: entry.book.title,
      occurredAt: loggedAt,
    );
  }

  /// `restart <book>` — puts a finished book back on the reading shelf at
  /// page 0 for another pass, bumping [UserBook.rereadCount] for the
  /// cover badge. Only valid once a book has actually been finished — a
  /// dropped ([ReadingStatus.dnf]) book isn't "restarted", it's just
  /// moved back with `move`.
  ///
  /// Uses [UserBookRepository.restart] rather than [_persist]: like
  /// [rateBook], `reread_count` isn't a column `saveProgress` writes.
  Future<LibraryActionResult> restartBook(
    String title, {
    DateTime? loggedAt,
  }) async {
    final entry = _findByTitle(title);
    if (entry == null) return _notStarted(title);
    if (!entry.isFinished) {
      return LibraryActionResult.failure(
        '"${entry.book.title}" hasn\'t been finished yet.',
      );
    }

    final invalidDate = _validateLoggedAt(loggedAt);
    if (invalidDate != null) return LibraryActionResult.failure(invalidDate);

    final previous = entry;
    final nextCount = entry.rereadCount + 1;
    _upsertLocal(
      entry.copyWith(
        progress: entry.progress.copyWith(
          currentPage: 0,
          status: ReadingStatus.reading,
          clearFinishedAt: true,
          rereadCount: nextCount,
        ),
      ),
    );
    notifyListeners();

    try {
      final saved = await userBooks.restart(
        userBookId: entry.progress.id,
        rereadCount: nextCount,
      );
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      _logEvent(
        ReadingEventType.restart,
        entry.book.title,
        occurredAt: loggedAt,
      );
      return LibraryActionResult.success('Restarted "${entry.book.title}"');
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
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
  ///
  /// A book not on the shelf is added as finished first (see
  /// [_onShelfOrAdd]) — rating a book says it was read.
  Future<LibraryActionResult> rateBook(String title, double rating) async {
    final existing = _findByTitle(title);
    if (existing != null) return _rateEntry(existing, rating);
    final resolved = await _onShelfOrAdd(
      title,
      ReadingStatus.finished,
      precheck: (_) => _validateRating(rating),
    );
    final entry = resolved.entry;
    if (entry == null) return resolved.failure!;
    final result = await _rateEntry(entry, rating);
    if (!resolved.added || !result.success) return result;
    return LibraryActionResult.success(
      'Added "${entry.book.title}" as finished — '
      '${formatCompactNumber(roundToHalf(rating))}★',
      true,
    );
  }

  /// The rating range rule [_rateEntry] enforces, as a message or null —
  /// shared so a fallback add can refuse a bad rating before adding.
  static String? _validateRating(double rating) {
    // Checked before rounding: `round()` throws on NaN and infinity, and a
    // long enough run of typed digits parses to infinity.
    if (!rating.isFinite) return 'Ratings are between 0.5 and 5 stars.';
    final rounded = roundToHalf(rating);
    if (rounded <= 0 || rounded > 5) {
      return 'Ratings are between 0.5 and 5 stars.';
    }
    return null;
  }

  /// The detail page's star row — [rateBook] for a row identified by id.
  Future<LibraryActionResult> rateBookById(String userBookId, double rating) {
    final entry = findById(userBookId);
    if (entry == null) return Future.value(_missingById);
    return _rateEntry(entry, rating);
  }

  Future<LibraryActionResult> _rateEntry(
    LibraryBook entry,
    double rating,
  ) async {
    if (!entry.isFinished) {
      return LibraryActionResult.failure(
        'Finish "${entry.book.title}" before rating it.',
      );
    }

    // Half-star granularity — rounded here (not just in the parser) so
    // the rule holds no matter who calls rateBook, and the star row
    // never has to render a value finer than it can actually display.
    if (_validateRating(rating) case final problem?) {
      return LibraryActionResult.failure(problem);
    }
    final rounded = roundToHalf(rating);

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
      _logEvent(ReadingEventType.rate, entry.book.title, value: rounded);
      return LibraryActionResult.success(
        '"${entry.book.title}" — ${formatCompactNumber(rounded)}★',
      );
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// The editions page's cover gallery: makes [edition] the copy the
  /// reader owns, or clears it with null.
  ///
  /// Owning an edition changes what the book *is* for this reader — its
  /// cover, publisher, length (see [LibraryBook.displayBook]) — so the
  /// page is rescaled to keep their place ([ShelfRules.pageForEdition])
  /// and saved in the same write. Optimistic with rollback, like every
  /// other shelf change. Only the reader's own shelf row changes; the
  /// shared catalogue entry is never touched.
  Future<LibraryActionResult> setOwnedEdition(
    String userBookId,
    BookEdition? edition,
  ) async {
    final entry = findById(userBookId);
    if (entry == null) return _missingById;
    final editionId = edition?.id;
    if (edition != null && editionId == null) {
      return const LibraryActionResult.failure(
        "That edition can't be selected yet — try again in a moment.",
      );
    }
    if (entry.progress.ownedEditionId == editionId) {
      return const LibraryActionResult.success();
    }

    final page = ShelfRules.pageForEdition(entry, edition);
    final previous = entry;
    final updated = entry.copyWith(
      progress: editionId == null
          ? entry.progress.copyWith(clearOwnedEdition: true, currentPage: page)
          : entry.progress.copyWith(
              ownedEditionId: editionId,
              currentPage: page,
            ),
      ownedEdition: edition,
      clearOwnedEdition: edition == null,
    );
    _upsertLocal(updated);
    notifyListeners();

    try {
      final saved = await userBooks.setOwnedEdition(
        userBookId,
        editionId,
        currentPage: page,
      );
      _upsertLocal(updated.copyWith(progress: saved));
      notifyListeners();

      final total = updated.pageCount;
      final moved = page != entry.currentPage && !entry.isFinished;
      final base = edition == null
          ? 'Cleared your edition'
          : 'Saved your edition';
      return LibraryActionResult.success(
        moved && total != null ? '$base — now page $page of $total' : base,
      );
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `add tag <tag> <book>` — applies a tag the reader already made to a
  /// book already on the shelf. A tag that doesn't exist is refused with the
  /// `make tag` command that would create it (see [noSuchTag]). Not
  /// optimistic: tags aren't rendered anywhere on the shelf itself, only on
  /// the detail page, which loads them fresh when it opens.
  ///
  /// A book not on the shelf yet is added to read first (see
  /// [_onShelfOrAdd]) — but only once the tag is known to exist, so a
  /// mistyped tag never leaves a stray book behind.
  Future<LibraryActionResult> addTag(String title, String tagName) async {
    if (noSuchTag(tagName) case final missing?) return missing;
    // Resolved now, not after the await below: a reload landing while the
    // book is being added could otherwise leave nothing to look up.
    final tag = findTag(tagName)!;
    final resolved = await _onShelfOrAdd(title, ReadingStatus.toBeRead);
    final entry = resolved.entry;
    if (entry == null) return resolved.failure!;
    try {
      final saved = await notes.addTag(entry.id, tag);
      notifyTagsChanged();
      return LibraryActionResult.success(
        resolved.added
            ? 'Added "${entry.book.title}" to read and tagged it ${saved.tag}'
            : 'Tagged "${entry.book.title}" ${saved.tag}',
        resolved.added,
      );
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// The failure for applying a tag the reader hasn't made — or null when
  /// [tagName] is a tag they have. Shared with the book page's tag field, so
  /// both surfaces refuse an unknown tag with the same words.
  LibraryActionResult? noSuchTag(String tagName) {
    final String clean;
    try {
      clean = CollectionNames.validateTag(tagName);
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
    if (findTag(clean) != null) return null;
    return LibraryActionResult.failure(unknownTagMessage(clean));
  }

  /// "No tag called …" — the one wording for a tag that hasn't been made.
  static String unknownTagMessage(String tagName) {
    final clean = CollectionNames.clean(tagName);
    return 'No tag called "$clean" yet — make it first with make tag $clean.';
  }

  /// `add comment <comment> <book>` — comments on a book already on the
  /// shelf. [title] is null when the comment wasn't quoted, in which case
  /// [comment] holds the whole unsplit argument ("loved the ending dune")
  /// and the book is found by [splitTrailingTitle].
  Future<LibraryActionResult> addComment(
    String comment, {
    String? title,
  }) async {
    var body = comment;
    final LibraryBook entry;
    var added = false;
    if (title != null) {
      // Validated before a fallback add, so an empty or overlong comment
      // never leaves a stray book on the shelf.
      try {
        BookNotesRepository.validateComment(comment);
      } on LibraryException catch (error) {
        return LibraryActionResult.failure(error.message);
      }
      final resolved = await _onShelfOrAdd(title, ReadingStatus.toBeRead);
      final found = resolved.entry;
      if (found == null) return resolved.failure!;
      entry = found;
      added = resolved.added;
    } else {
      final split = splitTrailingTitle(comment);
      if (split == null) {
        return const LibraryActionResult.failure(
          "Couldn't tell which book that comment is for — try "
          'add comment "your comment" <book>.',
        );
      }
      body = split.prefix;
      entry = split.entry;
    }

    try {
      await notes.addComment(entry.id, body);
      return LibraryActionResult.success(
        added
            ? 'Added "${entry.book.title}" to read and commented on it'
            : 'Commented on "${entry.book.title}"',
        added,
      );
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Splits "loved the ending dune messiah" into a leading comment and a
  /// book on the shelf, for an unquoted `add comment`. The parser can't do
  /// this — only the shelf knows where a comment stops and a title begins.
  ///
  /// Two passes: exact titles first, then [_findByTitle]'s fuzzy match.
  /// Within each pass the *longest* trailing run of words is tried first,
  /// so "Dune Messiah" wins over "Messiah". At least one word is always
  /// left over for the comment itself. Null when no trailing run of words
  /// names a book on the shelf.
  ({String prefix, LibraryBook entry})? splitTrailingTitle(String words) {
    final tokens = words.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2) return null;

    for (final exact in [true, false]) {
      for (var start = 1; start < tokens.length; start++) {
        final candidate = tokens.sublist(start).join(' ');
        final entry = exact
            ? _findExactTitle(candidate)
            : _findByTitle(candidate);
        if (entry != null) {
          return (prefix: tokens.sublist(0, start).join(' '), entry: entry);
        }
      }
    }
    return null;
  }

  /// Every series the reader has at least one book in — the library's
  /// series row.
  List<SeriesGroup> get seriesGroups =>
      SeriesGroup.fromShelf(_books, _mySeries);

  /// The series [id] refers to on the reader's own list, or null.
  BookSeries? seriesById(String id) {
    for (final s in _mySeries) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// [entry]'s series, formatted as "the expanse #2" — null when it isn't
  /// filed in one, or its series has since been removed from the reader's
  /// list.
  String? seriesLabelFor(LibraryBook entry) {
    final id = entry.seriesId;
    if (id == null) return null;
    final name = seriesById(id)?.name;
    if (name == null) return null;
    final position = entry.seriesPosition;
    return position == null
        ? name
        : '$name #${BookSeries.formatPosition(position)}';
  }

  /// `add series <series> [#n] <book>` — files a book on the shelf under a
  /// series already on the reader's list ([makeSeries]); an unknown series
  /// is refused with the `make series` command that would create it.
  /// Private to this reader, so a re-file keeps its old number when none is
  /// given and the book was already in that series, otherwise clears it —
  /// there is no other reader's spelling or number to defer to.
  Future<LibraryActionResult> addToSeries(
    String title,
    String seriesName, {
    double? position,
  }) async {
    final checked = _seriesToFile(seriesName, position);
    final known = checked.series;
    if (known == null) return checked.failure!;
    // Only now, with the series known to exist: a book not on the shelf
    // yet is added to read (see [_onShelfOrAdd]).
    final resolved = await _onShelfOrAdd(title, ReadingStatus.toBeRead);
    final entry = resolved.entry;
    if (entry == null) return resolved.failure!;
    return _fileInSeries(entry, known, position, added: resolved.added);
  }

  /// The book page's series picker — [addToSeries] for a row identified by
  /// id, so a book sharing its title with another can't be confused for it.
  Future<LibraryActionResult> addToSeriesById(
    String userBookId,
    String seriesName, {
    double? position,
  }) async {
    final entry = findById(userBookId);
    if (entry == null) return _missingById;
    final checked = _seriesToFile(seriesName, position);
    final known = checked.series;
    if (known == null) return checked.failure!;
    return _fileInSeries(entry, known, position, added: false);
  }

  /// The series [seriesName] names, once the name and [position] pass —
  /// or the failure saying why not. An unknown series is never created.
  ({BookSeries? series, LibraryActionResult? failure}) _seriesToFile(
    String seriesName,
    double? position,
  ) {
    final String clean;
    try {
      clean = CollectionNames.validateSeries(seriesName);
    } on LibraryException catch (error) {
      return (
        series: null,
        failure: LibraryActionResult.failure(error.message),
      );
    }
    final known = findSeries(clean);
    if (known == null) {
      return (
        series: null,
        failure: LibraryActionResult.failure(
          'No series called "$clean" yet — make it first with make series '
          '$clean.',
        ),
      );
    }
    if (position != null &&
        (!position.isFinite || position <= 0 || position >= 10000)) {
      return (
        series: null,
        failure: const LibraryActionResult.failure(
          'A series number has to be above 0 and below 10000.',
        ),
      );
    }
    return (series: known, failure: null);
  }

  Future<LibraryActionResult> _fileInSeries(
    LibraryBook entry,
    BookSeries known,
    double? position, {
    required bool added,
  }) async {
    final before = entry.progress;
    final samePosition = before.seriesId == known.id
        ? before.seriesPosition
        : null;
    final newPosition = position ?? samePosition;
    _upsertLocal(
      entry.copyWith(
        progress: before.copyWith(
          seriesId: known.id,
          seriesPosition: newPosition,
          clearSeriesPosition: newPosition == null,
        ),
      ),
    );
    notifyListeners();
    try {
      await series.setSeries(entry.id, known.id, position: newPosition);
      final label = newPosition == null
          ? known.name
          : '${known.name} #${BookSeries.formatPosition(newPosition)}';
      return LibraryActionResult.success(
        added
            ? 'Added "${entry.book.title}" to read and filed it under $label'
            : 'Filed "${entry.book.title}" under $label',
        added,
      );
    } on LibraryException catch (error) {
      _upsertLocal(entry.copyWith(progress: before));
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  // ---------------------------------------------------------------- removal

  /// Works out what a `remove shelf|tag|series` line means, using the
  /// collections that exist to split the name from a book title:
  ///
  /// * [name] given (the quoted form, `remove tag "sci fi" dune`) — the
  ///   parser already split it; [title] may be empty.
  /// * otherwise [argument] is the whole unquoted remainder ("summer reads
  ///   dune"): the *longest* leading run of words naming an existing
  ///   collection wins, and whatever follows is the book.
  ///
  /// No book at all means unmaking the collection itself
  /// ([UnmakeCollection]); a book means taking it out ([RemoveFromCollection]).
  /// Unknown names, and the built-in shelves (which aren't rows and can't be
  /// removed), come back as a failure message instead.
  ({CollectionRemoval? removal, String? failure}) resolveRemoval(
    CollectionKind kind, {
    String? name,
    String? title,
    String? argument,
  }) {
    String? matchedName;
    String remainder;
    if (name != null) {
      matchedName = name.trim();
      remainder = (title ?? '').trim();
    } else {
      final tokens = (argument ?? '').trim().split(RegExp(r'\s+'))
        ..removeWhere((t) => t.isEmpty);
      if (tokens.isEmpty) {
        return (
          removal: null,
          failure: 'Name the ${_singular(kind)} to remove.',
        );
      }
      remainder = '';
      matchedName = null;
      for (var end = tokens.length; end >= 1; end--) {
        final candidate = tokens.sublist(0, end).join(' ');
        if (_lookupCollection(kind, candidate) != null ||
            (kind == CollectionKind.shelves &&
                CollectionNames.builtInShelf(candidate) != null)) {
          matchedName = candidate;
          remainder = tokens.sublist(end).join(' ');
          break;
        }
      }
      matchedName ??= tokens.first;
    }

    if (matchedName.isEmpty) {
      return (removal: null, failure: 'Name the ${_singular(kind)} to remove.');
    }
    if (kind == CollectionKind.shelves &&
        CollectionNames.builtInShelf(matchedName) != null) {
      return (
        removal: null,
        failure:
            '"${CollectionNames.clean(matchedName)}" is a built-in shelf — it '
            "can't be removed.",
      );
    }
    final found = _lookupCollection(kind, matchedName);
    if (found == null) {
      final clean = CollectionNames.clean(matchedName);
      return (removal: null, failure: 'No ${_singular(kind)} called "$clean".');
    }
    if (remainder.isEmpty) {
      return (
        removal: UnmakeCollection(
          kind: kind,
          name: found.name,
          id: found.id,
          bookCount: switch (kind) {
            CollectionKind.shelves =>
              _books.where((b) => b.shelfId == found.id).length,
            CollectionKind.series =>
              _books.where((b) => b.seriesId == found.id).length,
            CollectionKind.tags => 0,
          },
        ),
        failure: null,
      );
    }
    return (
      removal: RemoveFromCollection(
        kind: kind,
        name: found.name,
        title: remainder,
      ),
      failure: null,
    );
  }

  ({String id, String name})? _lookupCollection(
    CollectionKind kind,
    String name,
  ) {
    final key = CollectionNames.key(name);
    switch (kind) {
      case CollectionKind.shelves:
        for (final s in _shelves) {
          if (CollectionNames.key(s.name) == key) {
            return (id: s.id, name: s.name);
          }
        }
      case CollectionKind.tags:
        for (final t in _tags) {
          if (CollectionNames.key(t.name) == key) {
            return (id: t.id, name: t.name);
          }
        }
      case CollectionKind.series:
        for (final s in _mySeries) {
          if (s.matches(name)) return (id: s.id, name: s.name);
        }
    }
    return null;
  }

  static String _singular(CollectionKind kind) => switch (kind) {
    CollectionKind.shelves => 'shelf',
    CollectionKind.tags => 'tag',
    CollectionKind.series => 'series',
  };

  /// Applies a resolved [removal] — see [resolveRemoval]. The add tab
  /// confirms an [UnmakeCollection] before calling this; the "+" panel
  /// calls [deleteShelf]/[deleteTag]/[deleteSeries] directly after its own
  /// confirmation.
  Future<LibraryActionResult> applyRemoval(CollectionRemoval removal) {
    return switch (removal) {
      UnmakeCollection(kind: CollectionKind.shelves, :final id) => deleteShelf(
        id,
      ),
      UnmakeCollection(kind: CollectionKind.tags, :final id) => deleteTag(id),
      UnmakeCollection(kind: CollectionKind.series, :final id) => deleteSeries(
        id,
      ),
      RemoveFromCollection(
        kind: CollectionKind.shelves,
        :final title,
        :final name,
      ) =>
        removeFromShelf(title, name),
      RemoveFromCollection(
        kind: CollectionKind.tags,
        :final title,
        :final name,
      ) =>
        removeTag(title, name),
      RemoveFromCollection(
        kind: CollectionKind.series,
        :final title,
        :final name,
      ) =>
        removeFromSeries(title, seriesName: name),
    };
  }

  /// `remove shelf <shelf> <book>` — takes a book off a custom shelf, back
  /// to its own status section with its progress kept (the same side effect
  /// a drag onto the built-in shelf of its status has). Refused for a book
  /// that isn't on that shelf.
  Future<LibraryActionResult> removeFromShelf(
    String title,
    String shelfName,
  ) async {
    final entry = _findByTitle(title);
    if (entry == null) return _notOnShelf(title);
    final target = findShelf(shelfName);
    if (target is! CustomShelfRef) {
      return LibraryActionResult.failure(
        'No shelf called "${CollectionNames.clean(shelfName)}".',
      );
    }
    if (entry.shelfId != target.shelfId) {
      return LibraryActionResult.failure(
        '"${entry.book.title}" isn\'t on ${shelfName.trim()}.',
      );
    }
    final result = await _changeShelf(entry, StatusShelfRef(entry.status));
    return result.success
        ? LibraryActionResult.success(
            'Took "${entry.book.title}" off ${shelfName.trim()}',
          )
        : result;
  }

  /// `remove tag <tag> <book>` — the reverse of [addTag]. Refused, without
  /// touching anything, when the book doesn't carry that tag. Not
  /// optimistic, like [addTag]: it needs a round trip to find which link
  /// row to delete anyway.
  Future<LibraryActionResult> removeTag(String title, String tagName) async {
    final entry = _findByTitle(title);
    if (entry == null) return _notOnShelf(title);
    final String clean;
    try {
      clean = CollectionNames.validateTag(tagName);
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
    try {
      final applied = await notes.fetchTags(entry.id);
      final match = applied
          .where((t) => BookTag.normalize(t.tag) == BookTag.normalize(clean))
          .firstOrNull;
      if (match == null) {
        return LibraryActionResult.failure(
          '"${entry.book.title}" isn\'t tagged $clean.',
        );
      }
      await notes.removeTag(match.id);
      notifyTagsChanged();
      return LibraryActionResult.success(
        'Removed $clean from "${entry.book.title}"',
      );
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// `remove series <series> <book>` — takes a book out of the series it's
  /// filed under, number and all. Refused when it isn't filed under that
  /// series. Optimistic with rollback, like [addToSeries].
  Future<LibraryActionResult> removeFromSeries(
    String title, {
    String? seriesName,
  }) async {
    final entry = _findByTitle(title);
    if (entry == null) return _notOnShelf(title);
    return _removeEntryFromSeries(entry, seriesName);
  }

  /// The book page's series chip and picker — [removeFromSeries] for a row
  /// identified by id. With no [seriesName], out of whatever series it's in.
  Future<LibraryActionResult> removeFromSeriesById(
    String userBookId, {
    String? seriesName,
  }) async {
    final entry = findById(userBookId);
    if (entry == null) return _missingById;
    return _removeEntryFromSeries(entry, seriesName);
  }

  Future<LibraryActionResult> _removeEntryFromSeries(
    LibraryBook entry,
    String? seriesName,
  ) async {
    final before = entry.progress;
    final currentId = before.seriesId;
    final known = seriesName == null
        ? (currentId == null ? null : seriesById(currentId))
        : findSeries(seriesName);
    if (known == null || currentId != known.id) {
      return LibraryActionResult.failure(
        seriesName == null
            ? '"${entry.book.title}" isn\'t in a series.'
            : '"${entry.book.title}" isn\'t filed under ${seriesName.trim()}.',
      );
    }
    _upsertLocal(
      entry.copyWith(
        progress: before.copyWith(
          clearSeriesId: true,
          clearSeriesPosition: true,
        ),
      ),
    );
    notifyListeners();
    try {
      await series.clearSeries(entry.id);
      return LibraryActionResult.success(
        'Took "${entry.book.title}" out of ${known.name}',
      );
    } on LibraryException catch (error) {
      _upsertLocal(entry.copyWith(progress: before));
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Unmakes a shelf — `remove shelf <shelf>` and the "+" panel's X. Every
  /// book on it falls back to its status section, progress untouched (the
  /// foreign key does this server-side; mirrored locally). Not optimistic:
  /// it's a confirmed, rarer action, and reverting a vanished section
  /// would be jarring.
  Future<LibraryActionResult> deleteShelf(String shelfId) async {
    final shelf = _shelfById(shelfId);
    if (shelf == null) {
      return const LibraryActionResult.failure("That shelf doesn't exist.");
    }
    try {
      await collections.deleteShelf(shelfId);
      _shelves = [..._shelves]..removeWhere((s) => s.id == shelfId);
      for (final entry in [..._books]) {
        if (entry.shelfId == shelfId) {
          _upsertLocal(
            entry.copyWith(
              progress: entry.progress.copyWith(
                clearShelfId: true,
                clearShelfPosition: true,
              ),
            ),
          );
        }
      }
      notifyListeners();
      return LibraryActionResult.success('Removed shelf "${shelf.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Unmakes a tag — `remove tag <tag>` and the "+" panel's X. Every book
  /// it was on loses it (the link rows cascade server-side).
  Future<LibraryActionResult> deleteTag(String tagId) async {
    final tag = _tags.where((t) => t.id == tagId).firstOrNull;
    if (tag == null) {
      return const LibraryActionResult.failure("That tag doesn't exist.");
    }
    try {
      await collections.deleteTag(tagId);
      _tags = [..._tags]..removeWhere((t) => t.id == tagId);
      notifyListeners();
      notifyTagsChanged();
      return LibraryActionResult.success('Removed tag "${tag.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Unmakes a series — `remove series <series>` and the "+" panel's X.
  /// Every book filed under it falls out of it, its number with it.
  Future<LibraryActionResult> deleteSeries(String seriesId) async {
    final found = seriesById(seriesId);
    if (found == null) {
      return const LibraryActionResult.failure("That series doesn't exist.");
    }
    try {
      await series.deleteSeries(seriesId);
      _mySeries = [..._mySeries]..removeWhere((s) => s.id == seriesId);
      for (final entry in [..._books]) {
        if (entry.seriesId == seriesId) {
          _upsertLocal(
            entry.copyWith(
              progress: entry.progress.copyWith(
                clearSeriesId: true,
                clearSeriesPosition: true,
              ),
            ),
          );
        }
      }
      notifyListeners();
      return LibraryActionResult.success('Removed series "${found.name}"');
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  /// Which comment a `remove comment` line means, for the add tab to
  /// confirm before [deleteComment] runs:
  ///
  /// * [title] given (quoted form) — [text] names the comment, or is null
  ///   for "the latest";
  /// * otherwise [argument] is split by [splitTrailingTitle]; if the whole
  ///   argument is itself a book's title, it's that book's latest comment.
  ///
  /// A comment matches ignoring case and surrounding space, then by prefix
  /// ("remove comment loved it dune" finds "loved it, especially the
  /// ending") — the most recent match wins.
  Future<({LibraryBook? entry, BookComment? comment, String? failure})>
  resolveCommentRemoval({String? title, String? text, String? argument}) async {
    LibraryBook? entry;
    String? needle;
    if (title != null) {
      entry = _findByTitle(title);
      if (entry == null) {
        return (
          entry: null,
          comment: null,
          failure: _notOnShelf(title).message,
        );
      }
      needle = text;
    } else {
      final words = (argument ?? '').trim();
      if (words.isEmpty) {
        return (
          entry: null,
          comment: null,
          failure: 'Name the book whose comment to remove.',
        );
      }
      entry = _findExactTitle(words);
      if (entry == null) {
        final split = splitTrailingTitle(words);
        if (split != null) {
          entry = split.entry;
          needle = split.prefix;
        } else {
          entry = _findByTitle(words);
        }
      }
      if (entry == null) {
        return (
          entry: null,
          comment: null,
          failure:
              "Couldn't tell which book that comment is on — try "
              'remove comment "the comment" <book>.',
        );
      }
    }

    try {
      final comments = [...await notes.fetchComments(entry.id)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (comments.isEmpty) {
        return (
          entry: entry,
          comment: null,
          failure: '"${entry.book.title}" has no comments.',
        );
      }
      if (needle == null || needle.trim().isEmpty) {
        return (entry: entry, comment: comments.first, failure: null);
      }
      final key = needle.trim().toLowerCase();
      final match =
          comments
              .where((c) => c.body.trim().toLowerCase() == key)
              .firstOrNull ??
          comments
              .where((c) => c.body.trim().toLowerCase().startsWith(key))
              .firstOrNull;
      if (match == null) {
        return (
          entry: entry,
          comment: null,
          failure:
              '"${entry.book.title}" has no comment like "${needle.trim()}".',
        );
      }
      return (entry: entry, comment: match, failure: null);
    } on LibraryException catch (error) {
      return (entry: entry, comment: null, failure: error.message);
    }
  }

  /// `remove comment` once confirmed — deletes [comment] from [entry].
  Future<LibraryActionResult> deleteComment(
    LibraryBook entry,
    BookComment comment,
  ) async {
    try {
      await notes.deleteComment(comment.id);
      return LibraryActionResult.success(
        'Removed a comment from "${entry.book.title}"',
      );
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
  }

  // ------------------------------------------------------------------ dates

  /// The book page's start/finish date fields. Both dates are calendar days
  /// (local midnight is fine); either may be omitted to keep the current
  /// one. Validation, before anything is written:
  ///
  /// * neither may be in the future;
  /// * a finish date is only for a finished book;
  /// * a book can't be finished before it was started.
  ///
  /// Optimistic with rollback, like every shelf write.
  Future<LibraryActionResult> setDates(
    String userBookId, {
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final entry = findById(userBookId);
    if (entry == null) return _missingById;
    final progress = entry.progress;

    if (finishedAt != null && !entry.isFinished) {
      return const LibraryActionResult.failure(
        'Only a finished book has a finish date.',
      );
    }
    final start = startedAt ?? progress.startedAt;
    final finish = finishedAt ?? progress.finishedAt;
    if (start == null) {
      return const LibraryActionResult.failure('Pick a start date first.');
    }
    final today = DateTime.now();
    final endOfToday = DateTime(today.year, today.month, today.day + 1);
    for (final date in [startedAt, finishedAt]) {
      if (date != null && !date.isBefore(endOfToday)) {
        return const LibraryActionResult.failure(
          "That date hasn't happened yet.",
        );
      }
    }
    if (entry.isFinished &&
        finish != null &&
        _dayOf(finish).isBefore(_dayOf(start))) {
      return const LibraryActionResult.failure(
        "A book can't be finished before it was started.",
      );
    }
    if (_sameMoment(start, progress.startedAt) &&
        (!entry.isFinished || _sameMoment(finish, progress.finishedAt))) {
      return const LibraryActionResult.success();
    }

    final previous = entry;
    _upsertLocal(
      entry.copyWith(
        progress: progress.copyWith(
          startedAt: start.toUtc(),
          finishedAt: entry.isFinished ? finish?.toUtc() : null,
        ),
      ),
    );
    notifyListeners();
    try {
      final saved = await userBooks.saveDates(
        userBookId,
        startedAt: start,
        finishedAt: entry.isFinished ? finish : null,
      );
      _upsertLocal(entry.copyWith(progress: saved));
      notifyListeners();
      return const LibraryActionResult.success('Saved your dates');
    } on LibraryException catch (error) {
      _upsertLocal(previous);
      notifyListeners();
      return LibraryActionResult.failure(error.message);
    }
  }

  static DateTime _dayOf(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static bool _sameMoment(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && a.isAtSameMomentAs(b);

  // ------------------------------------------------------ add-to-library

  /// Resolves [title] to a shelf row for a command that needs one —
  /// `update`, `finish`, `rate`, `add tag`, `add series`, a quoted
  /// `add comment` — *adding the book first* when it isn't on the shelf,
  /// the way `move` adds a book it doesn't find ([moveToShelf]).
  ///
  /// * On the shelf (by the usual fuzzy title match) — returned as is.
  /// * Otherwise the title is resolved cache-first through [lookup]; if
  ///   that finds a book already on the shelf under another spelling, that
  ///   row is used.
  /// * Otherwise [precheck] runs against a stand-in row for the book (so a
  ///   page past its end, a rating out of range, a percentage of a book of
  ///   unknown length refuses *before* anything is added), then the book is
  ///   added at [status] — reading, finished (at its last page), or to read
  ///   — with its start/finish dates at [at] when given, and journaled the
  ///   same way `move` journals an add.
  Future<({LibraryBook? entry, bool added, LibraryActionResult? failure})>
  _onShelfOrAdd(
    String title,
    ReadingStatus status, {
    DateTime? at,
    String? Function(LibraryBook candidate)? precheck,
  }) async {
    final onShelf = _findByTitle(title);
    if (onShelf != null) return (entry: onShelf, added: false, failure: null);

    try {
      final book = await lookup.findOrFetch(title);
      final existing = _findByBookId(book.id);
      if (existing != null) {
        return (entry: existing, added: false, failure: null);
      }

      final page = status == ReadingStatus.finished ? book.pageCount ?? 0 : 0;
      final problem = precheck?.call(
        LibraryBook(
          book: book,
          progress: UserBook(
            id: '',
            bookId: book.id,
            currentPage: page,
            status: status,
          ),
        ),
      );
      if (problem != null) {
        return (
          entry: null,
          added: false,
          failure: LibraryActionResult.failure(problem),
        );
      }

      final added = await userBooks.addWithStatus(
        book.id,
        status,
        currentPage: page,
        startedAt: at,
        finishedAt: status == ReadingStatus.finished ? at : null,
      );
      final entry = LibraryBook(book: book, progress: added.progress);
      _upsertLocal(entry);
      notifyListeners();
      _warmEditions(book);
      if (added.alreadyExists) {
        // Rare race: the row appeared between the local lookup and this
        // write. Use it as found rather than claiming an add.
        return (entry: entry, added: false, failure: null);
      }
      _logEvent(_eventForShelf(status), book.title, occurredAt: at);
      return (entry: entry, added: true, failure: null);
    } on LibraryException catch (error) {
      return (
        entry: null,
        added: false,
        failure: LibraryActionResult.failure(error.message),
      );
    }
  }

  /// [result], flagged as having added its book when [added].
  static LibraryActionResult _markAdded(
    LibraryActionResult result, {
    required bool added,
  }) {
    if (!added || !result.success) return result;
    return LibraryActionResult.success(result.message, true);
  }

  /// The "+" panel's books tab — [deleteBook] for a row identified by id,
  /// so two books with similar titles can never be confused.
  ///
  /// Deletes exactly that row. It used to re-resolve the book by its title,
  /// which with two books of the same title deleted whichever was updated
  /// most recently — not necessarily the one whose X was tapped.
  Future<LibraryActionResult> deleteBookById(String userBookId) {
    final entry = findById(userBookId);
    if (entry == null) return Future.value(_missingById);
    return _deleteEntry(entry);
  }

  /// `delete <book>` — removes the book from the shelf. Optimistic like
  /// the other commands: it disappears immediately, and comes back if
  /// the delete fails to persist.
  ///
  /// Also clears the book's whole journal history (see [_clearJournal])
  /// rather than logging one more "deleted" line — a book that's gone
  /// from the shelf shouldn't leave its "started"/"read up to page..."
  /// trail behind in the streak journal either. Its tags and comments go
  /// with the shelf row itself (`on delete cascade`).
  Future<LibraryActionResult> deleteBook(String title) {
    final entry = _findByTitle(title);
    if (entry == null) return Future.value(_notStarted(title));
    return _deleteEntry(entry);
  }

  Future<LibraryActionResult> _deleteEntry(LibraryBook entry) async {
    _removeLocal(entry.id);
    notifyListeners();

    try {
      await userBooks.delete(entry.id);
      _clearJournal(entry.book.title);
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
    double? value,
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
      _logEvent(loggedAs, title, occurredAt: occurredAt, value: value);
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

  static LibraryActionResult _notStarted(String title) =>
      LibraryActionResult.failure(
        'You haven\'t started "$title" yet — try "start $title" first.',
      );

  static LibraryActionResult _notOnShelf(String title) =>
      LibraryActionResult.failure(
        '"$title" isn\'t on your shelf yet — try "move $title tbr" first.',
      );

  static const _missingById = LibraryActionResult.failure(
    "That book isn't on your shelf any more.",
  );

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

  LibraryBook? _findExactTitle(String title) {
    final needle = title.trim().toLowerCase();
    for (final entry in _books) {
      if (entry.book.title.toLowerCase() == needle) return entry;
    }
    return null;
  }

  /// Resolves a book already on the shelf by its catalogue id rather
  /// than a typed title — used by [moveToShelf], which already has a
  /// resolved [Book] from [lookup] and needs the exact row, not a
  /// fuzzy title match.
  LibraryBook? _findByBookId(String bookId) {
    for (final entry in _books) {
      if (entry.book.id == bookId) return entry;
    }
    return null;
  }

  /// Inserts or replaces a shelf row, keyed on the `user_books` id.
  /// New books go to the front to match the "most recent first" order
  /// the server returns.
  ///
  /// A replacement built without the owned edition (a repeat `start`, an
  /// `move` race — anything that only had a `Book` and a `UserBook` to
  /// hand) keeps the edition the existing row already carried, as long as
  /// the progress row still points at it; otherwise the book's cover and
  /// length would silently revert to the work's until the next reload.
  void _upsertLocal(LibraryBook entry) {
    final index = _books.indexWhere((existing) => existing.id == entry.id);
    final next = [..._books];
    if (index == -1) {
      next.insert(0, entry);
    } else {
      final existing = next[index].ownedEdition;
      next[index] =
          entry.ownedEdition == null &&
              existing != null &&
              existing.id == entry.progress.ownedEditionId
          ? entry.copyWith(ownedEdition: existing)
          : entry;
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
