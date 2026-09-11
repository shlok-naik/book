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

  /// (Re)loads [year]. A second call for the same year that's already
  /// loaded is a no-op — the streaks page calls this once, on mount, and
  /// relies on [applyEvent] afterwards to pick up new commands rather
  /// than reloading the whole year again.
  Future<void> load(int year) async {
    if (_isLoading || _loadedYear == year) return;
    _isLoading = true;
    notifyListeners();

    try {
      final rows = await events.fetchForYear(year);
      final grouped = <DateTime, List<ReadingEvent>>{};
      for (final event in rows) {
        final key = _dayKey(event.occurredAt.toLocal());
        (grouped[key] ??= []).add(event);
      }
      _byDay = grouped;
      _loadedYear = year;
      _errorMessage = null;
    } on LibraryException catch (error) {
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
      _errorMessage = "We couldn't load your streak history.";
      AppLogger.error(
        'StreaksController',
        'Loading streak history failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
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
    notifyListeners();
  }
}
