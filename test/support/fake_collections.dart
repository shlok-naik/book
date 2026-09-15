import 'package:book/features/library/data/collections_repository.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_exception.dart';

/// In-memory `shelves` and `tags` — what `make shelf`/`make tag` and the
/// library's "+" panel write through `LibraryController`. Validates with the
/// real [CollectionNames] rules and refuses duplicates the way the unique
/// indexes do, so tests exercise the same failures the app would see.
class FakeCollectionsRepository extends CollectionsRepository {
  FakeCollectionsRepository({
    List<Shelf> shelves = const [],
    List<ReaderTag> tags = const [],
  }) : shelves = [...shelves],
       tags = [...tags];

  final List<Shelf> shelves;
  final List<ReaderTag> tags;

  /// Thrown by every call when set.
  LibraryException? failure;

  int creates = 0;

  @override
  Future<List<Shelf>> fetchShelves() async {
    if (failure != null) throw failure!;
    return List.of(shelves);
  }

  @override
  Future<List<ReaderTag>> fetchTags() async {
    if (failure != null) throw failure!;
    return List.of(tags);
  }

  @override
  Future<Shelf> createShelf(String name) async {
    final clean = CollectionNames.validateShelf(name);
    if (failure != null) throw failure!;
    if (shelves.any(
      (s) => CollectionNames.key(s.name) == clean.toLowerCase(),
    )) {
      throw InvalidInputException('You already have a shelf "$clean".');
    }
    creates++;
    final shelf = Shelf(id: 'shelf-${shelves.length + 1}', name: clean);
    shelves.add(shelf);
    return shelf;
  }

  @override
  Future<ReaderTag> createTag(String name) async {
    final clean = CollectionNames.validateTag(name);
    if (failure != null) throw failure!;
    if (tags.any((t) => CollectionNames.key(t.name) == clean.toLowerCase())) {
      throw InvalidInputException('You already have a tag "$clean".');
    }
    creates++;
    final tag = ReaderTag(id: 'tag-${tags.length + 1}', name: clean);
    tags.add(tag);
    return tag;
  }

  final deletedShelves = <String>[];
  final deletedTags = <String>[];

  @override
  Future<void> deleteShelf(String id) async {
    if (failure != null) throw failure!;
    shelves.removeWhere((s) => s.id == id);
    deletedShelves.add(id);
  }

  @override
  Future<void> deleteTag(String id) async {
    if (failure != null) throw failure!;
    tags.removeWhere((t) => t.id == id);
    deletedTags.add(id);
  }
}
