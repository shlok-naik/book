import 'package:flutter/foundation.dart';

import '../../../library/data/reading_event_repository.dart';
import '../../../library/domain/reading_event.dart';
import '../../domain/day_symbol.dart';

/// Loads a year of [ReadingEvent]s, grouped by local day — a symbol per
/// day for [MonthDotGrid], and the raw events themselves for the
/// day-detail sheet's command list.
class StreaksController extends ChangeNotifier {
  StreaksController({required this.events});

  final ReadingEventRepository events;

  Map<DateTime, List<ReadingEvent>> _byDay = const {};
  bool _isLoading = false;
  int? _loadedYear;

  bool get isLoading => _isLoading;

  static DateTime _dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// The symbol for [date], or null on a day nothing happened — the grid
  /// draws a dim open circle in that case.
  DaySymbol? symbolFor(DateTime date) {
    final events = _byDay[_dayKey(date)];
    if (events == null) return null;
    return DaySymbol.strongestOf(events.map((event) => event.type));
  }

  /// Every command logged on [date], oldest first — what the day-detail
  /// sheet lists.
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
    } catch (error) {
      debugPrint('StreaksController.load failed: $error');
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
