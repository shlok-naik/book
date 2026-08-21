import '../../library/domain/reading_event.dart';

/// What a day's dot on the streaks grid looks like, decided by the
/// strongest command logged that day.
///
/// A closed circle (finish) overpowers a hollow circle (start), which
/// overpowers a line (update/rate/delete) — so a day where a reader both
/// finishes one book and starts the next still reads as a closed circle,
/// not a line or a hollow one.
enum DaySymbol {
  line,
  hollowCircle,
  closedCircle;

  /// The symbol a single [type] earns on its own.
  static DaySymbol forType(ReadingEventType type) => switch (type) {
    ReadingEventType.finish => DaySymbol.closedCircle,
    ReadingEventType.start => DaySymbol.hollowCircle,
    ReadingEventType.update ||
    ReadingEventType.rate ||
    ReadingEventType.delete => DaySymbol.line,
  };

  /// How this symbol reads aloud, for the screen-reader description of
  /// a day on the grid. Describes what *happened*, not what is drawn —
  /// "finished a book" is the fact; "closed circle" is only how the grid
  /// happens to render it, and is no use to someone who cannot see it.
  String get spokenDescription => switch (this) {
    DaySymbol.closedCircle => 'finished a book',
    DaySymbol.hollowCircle => 'started a book',
    DaySymbol.line => 'logged reading',
  };

  /// The single symbol [types] resolves to, or null if [types] is empty
  /// (nothing happened that day, so the grid draws its default dot).
  static DaySymbol? strongestOf(Iterable<ReadingEventType> types) {
    DaySymbol? strongest;
    for (final type in types) {
      final symbol = forType(type);
      if (strongest == null || symbol.index > strongest.index) {
        strongest = symbol;
      }
    }
    return strongest;
  }
}
