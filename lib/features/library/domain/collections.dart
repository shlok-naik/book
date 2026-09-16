import 'library_exception.dart';
import 'user_book.dart';

// Standalone collections — shelves, tags and series a reader *makes first*
// and *applies to books afterwards*:
//
//   make shelf <name>   → [Shelf]          → move <book> <shelf>
//   make tag <tag>      → [ReaderTag]      → add tag <tag> <book>
//   make series <name>  → `BookSeries`     → add series <series> [#n] <book>
//
// Nothing that adds or changes a book creates one of these as a side effect.
// The typed `make` commands and the library page's "+" panel both reach the
// same creation functions on `LibraryController` (`makeShelf`, `makeTag`,
// `makeSeries`), which validate through [CollectionNames] before any I/O —
// so the two entry points can't disagree about what a valid name is.
//
// See `supabase/migrations/20260916000000_standalone_collections.sql` for the
// storage side.

/// The three kinds of collection a reader makes — the library "+" panel's
/// tabs, in order, and what `remove shelf|tag|series` acts on.
enum CollectionKind { shelves, tags, series }

/// What a `remove shelf|tag|series` line resolves to, once the collections
/// that exist can say where the collection's name ends and a book's title
/// begins — see `LibraryController.resolveRemoval`.
sealed class CollectionRemoval {
  const CollectionRemoval({required this.kind, required this.name});

  final CollectionKind kind;

  /// The collection's own stored name.
  final String name;
}

/// Unmake the collection itself — `remove shelf summer reads`, no book
/// named. Destructive for every book in it, so the add tab confirms first.
final class UnmakeCollection extends CollectionRemoval {
  const UnmakeCollection({
    required super.kind,
    required super.name,
    required this.id,
    required this.bookCount,
  });

  final String id;

  /// How many shelf books the collection holds (always 0 for a tag — tag
  /// membership isn't held on the shelf rows).
  final int bookCount;
}

/// Take one book out of the collection — `remove shelf summer reads dune`.
final class RemoveFromCollection extends CollectionRemoval {
  const RemoveFromCollection({
    required super.kind,
    required super.name,
    required this.title,
  });

  /// The book as typed; the library resolves it.
  final String title;
}

/// A shelf the reader made with `make shelf` — one row of `shelves`.
///
/// Custom shelves sit *alongside* the four built-in ones, which are not rows
/// at all but [ReadingStatus] values. A book on a custom shelf keeps its
/// status (so stats, the journal and "finished this year" still count it);
/// `user_books.shelf_id` only decides which section it is shown in.
class Shelf {
  const Shelf({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  /// Null (not a throw) for an unusable row — see `BookEdition.fromRow`.
  static Shelf? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    final created = row['created_at'];
    return Shelf(
      id: id,
      name: name.trim(),
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }
}

/// A tag the reader made with `make tag` — one row of `tags`. Applying it to
/// a book (`add tag`) creates a `book_tags` link row, represented by
/// `BookTag`.
class ReaderTag {
  const ReaderTag({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  static ReaderTag? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    final created = row['created_at'];
    return ReaderTag(
      id: id,
      name: name.trim(),
      createdAt: created is String ? DateTime.tryParse(created) : null,
    );
  }
}

/// Which section of the library a book is in, or is being moved to: one of
/// the four built-in status shelves, or a custom [Shelf].
///
/// Value-equal, so it can key maps and sets (the library page's collapsed
/// shelves) and be compared directly.
sealed class ShelfRef {
  const ShelfRef();

  /// Where [progress] is shown: its custom shelf when it has one, else its
  /// status shelf.
  factory ShelfRef.of(UserBook progress) {
    final shelfId = progress.shelfId;
    return shelfId == null
        ? StatusShelfRef(progress.status)
        : CustomShelfRef(shelfId);
  }
}

/// One of the four built-in shelves — reading, to read, finished, did not
/// finish.
final class StatusShelfRef extends ShelfRef {
  const StatusShelfRef(this.status);

  final ReadingStatus status;

  @override
  bool operator ==(Object other) =>
      other is StatusShelfRef && other.status == status;

  @override
  int get hashCode => Object.hash(StatusShelfRef, status);

  @override
  String toString() => 'StatusShelfRef(${status.name})';
}

/// A shelf the reader made, by its `shelves.id`.
final class CustomShelfRef extends ShelfRef {
  const CustomShelfRef(this.shelfId);

  final String shelfId;

  @override
  bool operator ==(Object other) =>
      other is CustomShelfRef && other.shelfId == shelfId;

  @override
  int get hashCode => Object.hash(CustomShelfRef, shelfId);

  @override
  String toString() => 'CustomShelfRef($shelfId)';
}

/// Name rules for every kind of collection, in one place — the parser's
/// commands, the "+" panel and the repositories all validate through here,
/// and each limit mirrors a check constraint in the migration so a bad name
/// is refused before a round-trip rather than by Postgres after one.
abstract final class CollectionNames {
  /// Matches `shelves.name`'s check constraint.
  static const shelfMaxLength = 40;

  /// Matches `tags.name` (and `book_tags.tag`).
  static const tagMaxLength = 40;

  /// Matches `series.name`.
  static const seriesMaxLength = 80;

  /// Every name (and alias) that already means a built-in shelf. `move`
  /// accepts all of them, and none can be used for a custom shelf — mirrors
  /// the `shelves_name_not_reserved` constraint.
  static const builtInShelves = <String, ReadingStatus>{
    'tbr': ReadingStatus.toBeRead,
    'to read': ReadingStatus.toBeRead,
    'to be read': ReadingStatus.toBeRead,
    'reading': ReadingStatus.reading,
    'finished': ReadingStatus.finished,
    'dnf': ReadingStatus.dnf,
    'did not finish': ReadingStatus.dnf,
  };

  /// Trimmed, inner whitespace collapsed — "  Summer   reads " is
  /// "Summer reads". The spelling that gets stored.
  static String clean(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The identity two names are compared by: [clean], then lowercased. The
  /// same normalisation the unique indexes use.
  static String key(String name) => clean(name).toLowerCase();

  /// The built-in shelf [name] refers to, or null for anything else.
  static ReadingStatus? builtInShelf(String name) => builtInShelves[key(name)];

  /// Cleans and validates a custom shelf name. Throws
  /// [InvalidInputException]; returns the cleaned name.
  static String validateShelf(String name) {
    final clean = _validate(name, kind: 'shelf', maxLength: shelfMaxLength);
    if (builtInShelf(clean) != null) {
      throw InvalidInputException('"$clean" is a built-in shelf.');
    }
    return clean;
  }

  static String validateTag(String name) =>
      _validate(name, kind: 'tag', maxLength: tagMaxLength);

  static String validateSeries(String name) =>
      _validate(name, kind: 'series', maxLength: seriesMaxLength);

  static String _validate(
    String name, {
    required String kind,
    required int maxLength,
  }) {
    final cleaned = clean(name);
    if (cleaned.isEmpty) {
      throw InvalidInputException('Name the $kind first.');
    }
    if (cleaned.length > maxLength) {
      throw InvalidInputException('Max $maxLength characters.');
    }
    return cleaned;
  }
}
