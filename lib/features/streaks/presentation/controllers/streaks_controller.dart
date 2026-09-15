import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../library/data/reading_event_repository.dart';
import '../../../library/domain/library_exception.dart';
import '../../../library/domain/reading_event.dart';

/// Loads a year of [ReadingEvent]s, grouped by local day, for the streak
/// page's journal — a line per command, newest day first.
class StreaksController extends ChangeNotifier {
  StreaksController({required this.events});

  final ReadingEventRepository events;

  Map<DateTime, List<ReadingEvent>> _byDay = const {};
  bool _isLoading = false;
  int? _loadedYear;
  String? _errorMessage;

  bool get isLoading => _isLoading;

  /// Set when the last [load] failed, so the page can say so and offer a
  /// retry instead of rendering an empty year as if it were real.
  String? get errorMessage => _errorMessage;

  static DateTime _dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Every day something was logged, most recent first — what the
  /// journal walks to build its list of date labels and entries.
  List<DateTime> get days =>
      _byDay.keys.toList()..sort((a, b) => b.compareTo(a));

  /// Every command logged on [date], oldest first — the order they
  /// actually happened in, so a day's entries read top-to-bottom like
  /// the rest of the story.
  List<ReadingEvent> eventsFor(DateTime date) =>
      List.unmodifiable(_byDay[_dayKey(date)] ?? const []);

  /// Every local day with something worth journaling on it — a day whose
  /// only command was a `delete` doesn't count.
  Set<DateTime> get loggedDays => {
    for (final MapEntry(key: day, value: events) in _byDay.entries)
      if (events.any((event) => event.type != ReadingEventType.delete)) day,
  };

  /// How many journaled commands landed on each local day — the stats
  /// page's heatmap intensity. Same exclusion as [loggedDays]: `delete`
  /// isn't a moment worth journaling, so it adds nothing, and a day of
  /// only deletes is absent.
  Map<DateTime, int> get activityByDay => {
    for (final MapEntry(key: day, value: events) in _byDay.entries)
      if (events.where((e) => e.type != ReadingEventType.delete).length
          case final count when count > 0)
        day: count,
  };

  /// Forgets what was loaded and loads [year] again — after the whole
  /// library was replaced (an import, a linked account's library).
  ///
  /// Supersedes a load already in flight rather than joining it: that one
  /// started before the library changed, so its answer is stale and is
  /// discarded when it lands.
  Future<void> reload(int year) {
    _loadedYear = null;
    _byDay = const {};
    _generation++;
    _inFlight = null;
    return load(year);
  }

  /// Bumped by every load that starts (and by [reload]); a load whose
  /// generation is no longer current when its fetch returns throws its
  /// answer away.
  int _generation = 0;
  Future<void>? _inFlight;
  int? _inFlightYear;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// (Re)loads [year]. A call for the year that's already loaded is a
  /// no-op, and a call for the year already *loading* joins that load —
  /// the streaks page calls this once, on mount, and relies on
  /// [applyEvent] afterwards to pick up new commands rather than reloading
  /// the whole year again.
  Future<void> load(int year) {
    if (_loadedYear == year) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null && _inFlightYear == year) return inFlight;
    final generation = ++_generation;
    _inFlightYear = year;
    return _inFlight = _load(year, generation).whenComplete(() {
      if (generation == _generation) _inFlight = null;
    });
  }

  Future<void> _load(int year, int generation) async {
    _isLoading = true;
    _notify();

    try {
      final rows = await events.fetchForYear(year);
      if (generation != _generation) return;
      final grouped = <DateTime, List<ReadingEvent>>{};
      for (final event in rows) {
        final key = _dayKey(event.occurredAt.toLocal());
        (grouped[key] ??= []).add(event);
      }
      _byDay = grouped;
      _loadedYear = year;
      _errorMessage = null;
    } on LibraryException catch (error) {
      if (generation != _generation) return;
      // Surfaced rather than swallowed: an empty journal and a failed
      // load used to look identical to the reader, so a Supabase outage
      // read as "you have never logged anything".
      _errorMessage = error.message;
      AppLogger.error(
        'StreaksController',
        'Loading streak history failed.',
        error: error,
      );
    } on Object catch (error, stackTrace) {
      if (generation != _generation) return;
      _errorMessage = "We couldn't load your streak history.";
      AppLogger.error(
        'StreaksController',
        'Loading streak history failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// Folds one freshly-logged [event] into the already-loaded state — how
  /// the streaks page picks up a shelf command without leaving and
  /// coming back, and without the full-year refetch a reload would cost.
  /// Ignored if it falls outside the loaded year, or before anything has
  /// loaded yet (the next [load] will pick it up anyway).
  void applyEvent(ReadingEvent event) {
    if (_loadedYear == null) return;
    final local = event.occurredAt.toLocal();
    if (local.year != _loadedYear) return;

    final key = _dayKey(local);
    _byDay = {
      ..._byDay,
      key: [...?_byDay[key], event],
    };
    _notify();
  }

  /// Drops every already-loaded event for [title] — the in-memory
  /// mirror of `ReadingEventRepository.deleteForTitle`, which does the
  /// actual Supabase delete. `delete <book>` fires this via
  /// `LibraryController.clearedTitles` so a deleted book's old lines
  /// disappear from an already-open journal without a reload.
  void removeTitle(String title) {
    final next = <DateTime, List<ReadingEvent>>{};
    var changed = false;
    for (final MapEntry(key: day, value: events) in _byDay.entries) {
      final kept = [
        for (final event in events)
          if (event.title != title) event,
      ];
      if (kept.length != events.length) changed = true;
      if (kept.isNotEmpty) next[day] = kept;
    }
    if (!changed) return;
    _byDay = next;
    _notify();
  }
}
