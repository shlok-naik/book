import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/domain/memory_exception.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMemoryRepository extends MemoryRepository {
  _FakeMemoryRepository({List<Memory> seed = const []}) : _memories = [...seed];

  final List<Memory> _memories;
  MemoryException? fetchFailure;
  MemoryException? addFailure;
  MemoryException? deleteFailure;
  int _nextId = 0;

  @override
  Future<List<Memory>> fetchAll() async {
    final failure = fetchFailure;
    if (failure != null) throw failure;
    // A copy, not the live list — the real repository builds a fresh
    // list from the query response every call, so a caller mutating
    // `_memories` afterward (as the "second load is a no-op" test
    // does, to prove the second call never re-fetches) must not also
    // reach into whatever `MemoryController` already stored.
    return [..._memories];
  }

  @override
  Future<Memory> add({String? bookTitle, required String note}) async {
    final failure = addFailure;
    if (failure != null) throw failure;
    final memory = Memory(
      id: 'saved-${_nextId++}',
      bookTitle: bookTitle,
      note: note,
      createdAt: DateTime(2026, 1, 1),
    );
    _memories.insert(0, memory);
    return memory;
  }

  @override
  Future<void> delete(String id) async {
    final failure = deleteFailure;
    if (failure != null) throw failure;
    _memories.removeWhere((memory) => memory.id == id);
  }
}

void main() {
  group('MemoryController.load', () {
    test('fetches every memory', () async {
      final repository = _FakeMemoryRepository(
        seed: [
          Memory(
            id: '1',
            bookTitle: 'Dune',
            note: 'loved the ending',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final controller = MemoryController(repository: repository);

      await controller.load();

      expect(controller.memories, hasLength(1));
      expect(controller.memories.single.bookTitle, 'Dune');
      expect(controller.errorMessage, isNull);
    });

    test('a second call is a no-op once the first has loaded', () async {
      final repository = _FakeMemoryRepository();
      final controller = MemoryController(repository: repository);

      await controller.load();
      // Prove the second call really is a no-op: seed a memory the
      // repository would return on a fresh fetch, then call load()
      // again — if it re-fetched, this would show up.
      repository._memories.add(
        Memory(
          id: '1',
          note: 'a note added after the first load',
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await controller.load();

      expect(controller.memories, isEmpty);
    });

    test('exposes a friendly message on failure', () async {
      final repository = _FakeMemoryRepository()
        ..fetchFailure = const MemoryException("We couldn't load that.");
      final controller = MemoryController(repository: repository);

      await controller.load();

      expect(controller.errorMessage, "We couldn't load that.");
      expect(controller.memories, isEmpty);
    });
  });

  group('MemoryController.remember', () {
    test('adds optimistically, then swaps in the persisted row', () async {
      final repository = _FakeMemoryRepository();
      final controller = MemoryController(repository: repository);

      final future = controller.remember(
        bookTitle: 'Dune',
        note: 'loved the ending',
      );
      // The optimistic entry is visible before the repository call
      // resolves.
      expect(controller.memories, hasLength(1));

      final result = await future;

      expect(result.success, isTrue);
      expect(controller.memories, hasLength(1));
      expect(controller.memories.single.id, 'saved-0');
      expect(controller.memories.single.note, 'loved the ending');
    });

    test('rolls the optimistic entry back on failure', () async {
      final repository = _FakeMemoryRepository()
        ..addFailure = const MemoryException("That memory didn't save.");
      final controller = MemoryController(repository: repository);

      final result = await controller.remember(
        bookTitle: 'Dune',
        note: 'loved the ending',
      );

      expect(result.success, isFalse);
      expect(result.message, "That memory didn't save.");
      expect(controller.memories, isEmpty);
    });

    test('notifies listeners on the optimistic add', () async {
      final controller = MemoryController(repository: _FakeMemoryRepository());
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.remember(bookTitle: 'Dune', note: 'note');

      expect(notifications, greaterThan(0));
    });
  });

  group('MemoryController.forget', () {
    test('removes optimistically and persists the delete', () async {
      final repository = _FakeMemoryRepository(
        seed: [
          Memory(id: '1', note: 'a note', createdAt: DateTime(2026, 1, 1)),
        ],
      );
      final controller = MemoryController(repository: repository);
      await controller.load();

      final result = await controller.forget('1');

      expect(result.success, isTrue);
      expect(controller.memories, isEmpty);
      expect(await repository.fetchAll(), isEmpty);
    });

    test('restores the entry on a failed delete', () async {
      final memory = Memory(
        id: '1',
        note: 'a note',
        createdAt: DateTime(2026, 1, 1),
      );
      final repository = _FakeMemoryRepository(seed: [memory])
        ..deleteFailure = const MemoryException("That didn't work.");
      final controller = MemoryController(repository: repository);
      await controller.load();

      final result = await controller.forget('1');

      expect(result.success, isFalse);
      expect(controller.memories, hasLength(1));
      expect(controller.memories.single.id, '1');
    });
  });
}
