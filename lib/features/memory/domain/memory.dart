/// One reader-authored note about how a book made them feel —
/// `remember <book> :: <note>`, captured by cactus pro's
/// natural-language mode and shown back in the profile page's own
/// memory list. Fed to the `parse-command` edge function as grounding
/// for `recommend` (see `HomePage._recommendContext`).
class Memory {
  const Memory({
    required this.id,
    required this.note,
    required this.createdAt,
    this.bookTitle,
  });

  final String id;

  /// The book the note is about — null for a general preference with
  /// nothing to attach a title to ("I always end up disappointed by
  /// hyped-up fantasy").
  final String? bookTitle;

  final String note;
  final DateTime createdAt;

  /// Parses one row from the `memories` table — null (rather than a
  /// throw) for a row missing something required, the same
  /// defensive-parse convention `ReadingEvent.fromRow` uses, so one bad
  /// row degrades to "skipped" instead of failing the whole fetch.
  static Memory? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final note = row['note'];
    final createdAt = row['created_at'];
    if (id is! String || note is! String || createdAt is! String) {
      return null;
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) return null;

    return Memory(
      id: id,
      bookTitle: row['book_title'] as String?,
      note: note,
      createdAt: parsedCreatedAt,
    );
  }
}
