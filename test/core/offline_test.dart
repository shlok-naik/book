import 'dart:io';

import 'package:book/core/network/connectivity_controller.dart';
import 'package:book/core/offline/offline_store.dart';
import 'package:book/core/offline/pending_write.dart';
import 'package:book/core/offline/pending_write_queue.dart';
import 'package:book/core/offline/sync_coordinator.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/features/library/data/offline_library_cache.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offline mode: the write queue, the coordinator that drains it, the raw
/// row cache, and the repositories' offline paths. None of it touches
/// Supabase — with connectivity forced offline, a repository never makes a
/// request, which is exactly the behaviour under test.

PendingUpdate _update(String id, String rowId, Map<String, Object?> values) =>
    PendingUpdate(
      id: id,
      createdAt: DateTime.utc(2026, 9, 14),
      table: 'user_books',
      rowId: rowId,
      values: values,
    );

/// A `user_books` row with its `book` embedded, as the shelf query returns.
Map<String, dynamic> _shelfRow(
  String id, {
  String title = 'Dune',
  int page = 0,
  String status = 'reading',
  String updatedAt = '2026-09-01T00:00:00Z',
  double? position,
}) => {
  'id': id,
  'book_id': 'book-$id',
  'current_page': page,
  'status': status,
  'updated_at': updatedAt,
  'shelf_position': position,
  'book': {'id': 'book-$id', 'title': title, 'author': 'Frank Herbert'},
};

/// Applies everything, and enqueues [enqueue] right after executing the
/// write with id [after] — a reader making a change mid-drain.
class _EnqueueingExecutor implements PendingWriteExecutor {
  _EnqueueingExecutor(this.queue, {required this.after, required this.enqueue});

  final PendingWriteQueue queue;
  final String after;
  final PendingWrite enqueue;
  final executed = <String>[];

  @override
  Future<ReplayOutcome> execute(PendingWrite write) async {
    executed.add(write.id);
    if (write.id == after) await queue.enqueue(enqueue);
    return ReplayOutcome.applied;
  }
}

class _FakeExecutor implements PendingWriteExecutor {
  _FakeExecutor(this.outcomes);

  /// Outcome per write id; anything unlisted applies.
  final Map<String, ReplayOutcome> outcomes;
  final executed = <String>[];

  @override
  Future<ReplayOutcome> execute(PendingWrite write) async {
    executed.add(write.id);
    return outcomes[write.id] ?? ReplayOutcome.applied;
  }
}

void main() {
  tearDown(ConnectivityController.reset);

  group('PendingWriteQueue', () {
    test('persists across instances, in order', () async {
      final store = MemoryOfflineStore();
      final queue = PendingWriteQueue(store: store);
      await queue.enqueue(_update('a', 'row-1', {'rating': 4}));
      await queue.enqueue(
        PendingDelete(
          id: 'b',
          createdAt: DateTime.utc(2026),
          table: 'user_books',
          column: 'id',
          value: 'row-2',
        ),
      );
      expect(queue.pendingCount.value, 2);

      final reopened = PendingWriteQueue(store: store);
      final writes = await reopened.snapshot();
      expect(writes.map((w) => w.id), ['a', 'b']);
      expect(writes.first, isA<PendingUpdate>());
      expect((writes.first as PendingUpdate).values, {'rating': 4});
      expect(reopened.pendingCount.value, 2);
    });

    test(
      'merges an update into the last entry only when it is the same row',
      () async {
        final queue = PendingWriteQueue(store: MemoryOfflineStore());
        await queue.enqueue(_update('a', 'row-1', {'current_page': 10}));
        await queue.enqueue(
          _update('b', 'row-1', {'current_page': 20, 'status': 'reading'}),
        );
        await queue.enqueue(_update('c', 'row-2', {'rating': 5}));
        // Not merged into 'a': 'c' sits between them.
        await queue.enqueue(_update('d', 'row-1', {'current_page': 30}));

        final writes = await queue.snapshot();
        expect(writes.map((w) => w.id), ['a', 'c', 'd']);
        expect((writes.first as PendingUpdate).values, {
          'current_page': 20,
          'status': 'reading',
        });
      },
    );

    test('skips stored entries it does not understand', () async {
      final store = MemoryOfflineStore();
      await store.write('pending_writes', [
        {'op': 'teleport', 'id': 'x', 'created_at': '2026-01-01T00:00:00Z'},
        _update('a', 'row-1', {'rating': 3}).toJson(),
        'garbage',
      ]);
      final writes = await PendingWriteQueue(store: store).snapshot();
      expect(writes.map((w) => w.id), ['a']);
    });
  });

  group('SyncCoordinator', () {
    test('replays in order, drops refusals, and reloads afterwards', () async {
      final queue = PendingWriteQueue(store: MemoryOfflineStore());
      await queue.enqueue(_update('a', 'row-1', {'rating': 1}));
      await queue.enqueue(_update('b', 'row-2', {'rating': 2}));
      await queue.enqueue(_update('c', 'row-3', {'rating': 3}));
      final executor = _FakeExecutor({'b': ReplayOutcome.rejected});
      var reloads = 0;
      final sync = SyncCoordinator(
        queue: queue,
        executor: executor,
        onSynced: () async => reloads++,
      );

      await sync.flush();
      await pumpEventQueue();

      expect(executor.executed, ['a', 'b', 'c']);
      expect(await queue.isEmpty, isTrue);
      expect(sync.lastRejected.value, 1);
      expect(reloads, 1);
    });

    test('stops at the first unreachable write and keeps the rest', () async {
      final queue = PendingWriteQueue(store: MemoryOfflineStore());
      await queue.enqueue(_update('a', 'row-1', {'rating': 1}));
      await queue.enqueue(_update('b', 'row-2', {'rating': 2}));
      await queue.enqueue(_update('c', 'row-3', {'rating': 3}));
      final executor = _FakeExecutor({'b': ReplayOutcome.unreachable});
      final sync = SyncCoordinator(queue: queue, executor: executor);

      await sync.flush();

      expect(executor.executed, ['a', 'b']);
      expect((await queue.snapshot()).map((w) => w.id), ['b', 'c']);
    });

    test('does nothing while offline, and drains on reconnect', () async {
      ConnectivityController.debugSetOffline(true);
      final queue = PendingWriteQueue(store: MemoryOfflineStore());
      await queue.enqueue(_update('a', 'row-1', {'rating': 1}));
      final executor = _FakeExecutor(const {});
      final sync = SyncCoordinator(queue: queue, executor: executor)..start();
      addTearDown(sync.dispose);

      await sync.flush();
      expect(executor.executed, isEmpty);

      ConnectivityController.debugSetOffline(false);
      await pumpEventQueue();
      expect(executor.executed, ['a']);
      expect(await queue.isEmpty, isTrue);
    });
  });

  group('ordering and storage (audit regressions)', () {
    test('a write queued during a drain goes out in the same flush', () async {
      final queue = PendingWriteQueue(store: MemoryOfflineStore());
      await queue.enqueue(_update('a', 'row-1', {'rating': 1}));
      final executor = _EnqueueingExecutor(
        queue,
        after: 'a',
        enqueue: _update('b', 'row-2', {'rating': 2}),
      );
      final sync = SyncCoordinator(queue: queue, executor: executor);

      await sync.flush();

      expect(executor.executed, ['a', 'b']);
      expect(await queue.isEmpty, isTrue);
    });

    test('online, a write made while older ones wait is queued behind them '
        'rather than sent ahead', () async {
      final queue = PendingWriteQueue(store: MemoryOfflineStore());
      final executor = _FakeExecutor({'old': ReplayOutcome.unreachable});
      final sync = SyncCoordinator(queue: queue, executor: executor);
      final offline = OfflineLibraryCache(
        accountId: 'me',
        store: MemoryOfflineStore(),
        queue: queue,
        sync: sync,
        currentUserId: () => 'me',
      );
      await offline.writeShelf([_shelfRow('r1', page: 10)]);
      // Written offline, still waiting: the drain stopped at it.
      await queue.enqueue(_update('old', 'r1', {'current_page': 50}));
      ConnectivityController.debugSetOffline(false);

      final repository = UserBookRepository(offline: offline);
      final saved = await repository.saveProgress(
        userBookId: 'r1',
        currentPage: 60,
        finished: false,
      );
      await pumpEventQueue();

      expect(saved.currentPage, 60);
      // Not sent ahead of the waiting write (without Supabase that would
      // have thrown): folded into it, so the one replay carries the newest
      // value and 50 can never land over 60.
      final waiting = await queue.snapshot();
      expect(waiting, hasLength(1));
      expect((waiting.single as PendingUpdate).values['current_page'], 60);
    });

    test('overlapping file writes to one key leave a readable, latest '
        'document', () async {
      final dir = await Directory.systemTemp.createTemp('offline_store_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileOfflineStore(accountId: 'me', root: () async => dir);

      await Future.wait([
        for (var i = 0; i < 25; i++)
          store.write('pending_writes', [
            for (var j = 0; j <= i; j++) {'n': j, 'pad': 'x' * 200},
          ]),
      ]);

      final read = await store.read('pending_writes');
      expect(read, isA<List<Object?>>());
      expect((read! as List).length, 25);
    });
  });

  group('OfflineLibraryCache', () {
    OfflineLibraryCache cache({String? user = 'me'}) => OfflineLibraryCache(
      accountId: 'me',
      store: MemoryOfflineStore(),
      queue: PendingWriteQueue(store: MemoryOfflineStore()),
      currentUserId: () => user,
    );

    test('a status change bumps updated_at and clears the manual position, '
        'a position-only change does neither', () async {
      final offline = cache();
      await offline.writeShelf([_shelfRow('r1', position: 2)]);

      final placed = await offline.patchShelfRow('r1', {'shelf_position': 0});
      expect(placed!['updated_at'], '2026-09-01T00:00:00Z');
      expect(placed['shelf_position'], 0);

      final moved = await offline.patchShelfRow('r1', {'status': 'finished'});
      expect(moved!['shelf_position'], isNull);
      expect(moved['updated_at'], isNot('2026-09-01T00:00:00Z'));
      // The embedded book survives a patch.
      expect((moved['book'] as Map)['title'], 'Dune');
    });

    test('an uncached row cannot be patched', () async {
      final offline = cache();
      await offline.writeShelf([_shelfRow('r1')]);
      expect(await offline.patchShelfRow('nope', {'rating': 5}), isNull);
    });

    test(
      'belongs to one account — another signed-in uid sees no cache',
      () async {
        final offline = cache(user: 'someone-else');
        await offline.writeShelf([_shelfRow('r1')]);
        expect(await offline.readShelf(), isNull);
        expect(offline.isActive, isFalse);
      },
    );
  });

  group('UserBookRepository offline', () {
    late OfflineLibraryCache offline;
    late UserBookRepository repository;

    setUp(() async {
      offline = OfflineLibraryCache(
        accountId: 'me',
        store: MemoryOfflineStore(),
        queue: PendingWriteQueue(store: MemoryOfflineStore()),
        currentUserId: () => 'me',
      );
      await offline.writeShelf([
        _shelfRow('r1', title: 'Dune', updatedAt: '2026-09-01T00:00:00Z'),
        _shelfRow('r2', title: 'Emma', updatedAt: '2026-09-02T00:00:00Z'),
      ]);
      repository = UserBookRepository(offline: offline);
      ConnectivityController.debugSetOffline(true);
    });

    test('progress saves locally, queues the same update, and survives a '
        'reload', () async {
      final saved = await repository.saveProgress(
        userBookId: 'r1',
        currentPage: 120,
        finished: false,
      );
      expect(saved.currentPage, 120);

      final writes = await offline.queue.snapshot();
      expect(writes.single, isA<PendingUpdate>());
      expect((writes.single as PendingUpdate).values['current_page'], 120);

      final shelf = await repository.fetchLibrary();
      // Dune was just touched, so it now sorts first.
      expect(shelf.map((b) => b.book.title), ['Dune', 'Emma']);
      expect(shelf.first.currentPage, 120);
    });

    test('a move, a rating and a delete all work offline', () async {
      final moved = await repository.changeShelf(
        const UserBook(
          id: 'r2',
          bookId: 'book-r2',
          currentPage: 300,
          status: ReadingStatus.finished,
        ),
      );
      expect(moved.status, ReadingStatus.finished);

      final rated = await repository.rate(userBookId: 'r2', rating: 4.5);
      expect(rated.rating, 4.5);

      await repository.delete('r1');

      final shelf = await repository.fetchLibrary();
      expect(shelf.single.book.title, 'Emma');
      expect(shelf.single.rating, 4.5);
      expect(await offline.queue.snapshot(), hasLength(2)); // merged + delete
    });

    test('the shelf order is applied locally and queued as the rpc', () async {
      await repository.saveShelfOrder(['r2', 'r1']);
      final shelf = await repository.fetchLibrary();
      expect(
        {for (final b in shelf) b.book.title: b.progress.shelfPosition},
        {'Emma': 0, 'Dune': 1},
      );
      final rpc = (await offline.queue.snapshot()).single as PendingRpc;
      expect(rpc.function, 'set_shelf_order');
    });

    test(
      'a book that was never cached fails with the offline message',
      () async {
        await expectLater(
          repository.rate(userBookId: 'unknown', rating: 3),
          throwsA(isA<NetworkException>()),
        );
        expect(await offline.queue.isEmpty, isTrue);
      },
    );
  });

  group('ReadingEventRepository offline', () {
    test(
      'a logged event joins the cached year and is queued with its time',
      () async {
        ConnectivityController.debugSetOffline(true);
        final offline = OfflineLibraryCache(
          accountId: 'me',
          store: MemoryOfflineStore(),
          queue: PendingWriteQueue(store: MemoryOfflineStore()),
          currentUserId: () => 'me',
        );
        final repository = ReadingEventRepository(offline: offline);
        final at = DateTime.now();

        await repository.log(
          ReadingEventType.update,
          title: 'Dune',
          occurredAt: at,
          value: 40,
        );

        final events = await repository.fetchForYear(at.year);
        expect(events.single.title, 'Dune');
        expect(events.single.value, 40);
        final insert = (await offline.queue.snapshot()).single as PendingInsert;
        expect(insert.values['occurred_at'], at.toUtc().toIso8601String());

        await repository.deleteForTitle('Dune');
        expect(await repository.fetchForYear(at.year), isEmpty);
      },
    );
  });

  group('PlanController', () {
    tearDown(PlanController.reset);

    test('is pro when entitled or when the debug override is on', () {
      expect(PlanController.isPro.value, isFalse);

      PlanController.updateEntitlement(true);
      expect(PlanController.isPro.value, isTrue);
      expect(PlanController.isEntitled, isTrue);

      PlanController.updateEntitlement(false);
      expect(PlanController.isPro.value, isFalse);

      PlanController.toggle();
      expect(PlanController.isPro.value, isTrue);
      expect(PlanController.isEntitled, isFalse);

      // Losing a subscription doesn't switch off the debug override.
      PlanController.updateEntitlement(false);
      expect(PlanController.isPro.value, isTrue);
    });
  });
}
