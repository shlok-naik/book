/// Which shelf command produced a [ReadingEvent] — logged alongside every
/// successful `LibraryController` mutation so the streaks page can read
/// back what happened on a given day.
enum ReadingEventType {
  start,
  update,
  finish,
  rate,
  delete;

  /// Column value stored in Supabase. Lowercase, matches the name — kept
  /// as a string (not an int) so the table stays readable in the
  /// dashboard, same convention as `ReadingStatus.wireValue`.
  String get wireValue => name;

  static ReadingEventType? fromWire(Object? value) {
    for (final type in ReadingEventType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

/// A row of the Supabase `reading_events` table: one shelf command that
/// actually took effect, and when.
class ReadingEvent {
  const ReadingEvent({
    required this.type,
    required this.occurredAt,
    this.title,
  });

  final ReadingEventType type;
  final DateTime occurredAt;

  /// The book the command was about — null only for a row written before
  /// this column existed. Carried along purely for the day-detail sheet's
  /// list; nothing in the streak grid itself reads it.
  final String? title;

  /// Parses a `reading_events` row. Unlike `UserBook.fromRow`, a bad row
  /// here isn't fatal to the whole page — the streaks grid just treats
  /// that one day as if nothing happened — so this returns null instead
  /// of throwing, and callers filter unparseable rows out.
  static ReadingEvent? fromRow(Map<String, dynamic> row) {
    final type = ReadingEventType.fromWire(row['action']);
    final rawDate = row['occurred_at'];
    final occurredAt = rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (type == null || occurredAt == null) return null;
    final rawTitle = row['title'];
    return ReadingEvent(
      type: type,
      occurredAt: occurredAt,
      title: rawTitle is String && rawTitle.isNotEmpty ? rawTitle : null,
    );
  }
}
