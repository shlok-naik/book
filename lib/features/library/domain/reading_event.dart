/// Which shelf command produced a [ReadingEvent] — logged alongside every
/// successful `LibraryController` mutation so the streaks page can read
/// back what happened on a given day.
enum ReadingEventType {
  start,
  update,
  finish,
  rate,
  delete,

  /// `add <book> tbr` — `add <book> finished` logs as [finish] instead,
  /// since that's exactly what happened; there's nothing else to name.
  addToBeRead,

  /// `add <book> dnf`.
  dnf,

  /// `restart <book>` — a finished book put back on the reading shelf for
  /// another pass.
  restart;

  /// Column value stored in Supabase. Lowercase, matches the name for
  /// every other value — kept as a string (not an int) so the table
  /// stays readable in the dashboard, same convention as
  /// `ReadingStatus.wireValue`. [addToBeRead] needs its own mapping
  /// since its Dart name isn't already snake_case.
  String get wireValue => switch (this) {
    ReadingEventType.addToBeRead => 'add_to_be_read',
    _ => name,
  };

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
    this.value,
  });

  final ReadingEventType type;
  final DateTime occurredAt;

  /// The book the command was about — null only for a row written before
  /// this column existed. Carried along purely for the journal page's
  /// list; nothing else reads it.
  final String? title;

  /// The number the command carried — the page an `update` reached, or
  /// the rating a `rate` gave. Null for `start`/`finish`/`delete`, which
  /// have nothing numeric to say, and for any row written before this
  /// column existed.
  final double? value;

  /// Parses a `reading_events` row. Unlike `UserBook.fromRow`, a bad row
  /// here isn't fatal to the whole page — the journal just treats that
  /// one day as if nothing happened — so this returns null instead of
  /// throwing, and callers filter unparseable rows out.
  static ReadingEvent? fromRow(Map<String, dynamic> row) {
    final type = ReadingEventType.fromWire(row['action']);
    final rawDate = row['occurred_at'];
    final occurredAt = rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (type == null || occurredAt == null) return null;
    final rawTitle = row['title'];
    final rawValue = row['value'];
    return ReadingEvent(
      type: type,
      occurredAt: occurredAt,
      title: rawTitle is String && rawTitle.isNotEmpty ? rawTitle : null,
      value: rawValue is num ? rawValue.toDouble() : null,
    );
  }
}
