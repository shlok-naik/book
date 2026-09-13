/// A reader's own label on a book on their shelf — `add tag <tag> <book>`,
/// or the tags section of the book detail page. A row of `book_tags`.
class BookTag {
  const BookTag({
    required this.id,
    required this.userBookId,
    required this.tag,
    required this.createdAt,
  });

  final String id;
  final String userBookId;
  final String tag;
  final DateTime createdAt;

  /// Longest tag accepted — matches the `book_tags.tag` check constraint,
  /// so an overlong tag is refused before a round-trip rather than by
  /// Postgres after one.
  static const maxLength = 40;

  /// Tags are compared ignoring case and surrounding space ("Sci-Fi" and
  /// "sci-fi " are the same tag) — the same rule the unique index on
  /// `lower(btrim(tag))` enforces server-side.
  static String normalize(String tag) => tag.trim().toLowerCase();

  /// Null (not a throw) for an unusable row — see `BookEdition.fromRow`.
  static BookTag? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final userBookId = row['user_book_id'];
    final tag = row['tag'];
    final createdAt = row['created_at'];
    if (id is! String ||
        userBookId is! String ||
        tag is! String ||
        createdAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return null;
    return BookTag(id: id, userBookId: userBookId, tag: tag, createdAt: parsed);
  }
}

/// A reader's free-text note on a book on their shelf —
/// `add comment <comment> <book>`, or the comments section of the book detail page. On
/// a DNF book this is where the reason for giving up goes. A row of
/// `book_comments`.
class BookComment {
  const BookComment({
    required this.id,
    required this.userBookId,
    required this.body,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userBookId;
  final String body;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Matches the `book_comments.body` check constraint.
  static const maxLength = 1000;

  /// Whether the comment was edited after it was written. A second of
  /// slack, because the insert itself sets both columns from two separate
  /// `now()`-ish defaults.
  bool get isEdited {
    final updated = updatedAt;
    return updated != null && updated.difference(createdAt).inSeconds >= 1;
  }

  BookComment copyWith({String? body, DateTime? updatedAt}) => BookComment(
    id: id,
    userBookId: userBookId,
    body: body ?? this.body,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static BookComment? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final userBookId = row['user_book_id'];
    final body = row['body'];
    final createdAt = row['created_at'];
    if (id is! String ||
        userBookId is! String ||
        body is! String ||
        createdAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) return null;
    final updatedAt = row['updated_at'];
    return BookComment(
      id: id,
      userBookId: userBookId,
      body: body,
      createdAt: parsed,
      updatedAt: updatedAt is String ? DateTime.tryParse(updatedAt) : null,
    );
  }
}
