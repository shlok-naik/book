import 'dart:async';

import '../../../core/diagnostics/app_logger.dart';
import '../../../core/network/connectivity_controller.dart';
import '../../../core/offline/offline_store.dart';
import '../../../core/offline/pending_write.dart';
import '../../../core/offline/pending_write_queue.dart';
import '../../../core/offline/sync_coordinator.dart';

/// What lets the library keep working without a connection: the last
/// shelf and journal the server returned, kept as the *raw rows* it
/// returned them as, plus the queue offline writes go into.
///
/// Raw rows rather than serialized models, on purpose. An offline write
/// patches the cached row with exactly the column values it would have
/// sent to Supabase, and the shelf is re-parsed by the same
/// `UserBook.fromRow`/`Book.fromRow` code an online load uses — so there is
/// no second serialization format to drift out of step with the schema.
///
/// Injected into `UserBookRepository` and `ReadingEventRepository` by the
/// composition root; both behave exactly as before when it's absent (every
/// test that doesn't opt in).
///
/// Scoped to one account ([accountId]). If the signed-in uid changes under
/// it — linking an email that swaps this device onto another account's
/// library — [isActive] turns false and the repositories stop reading the
/// cache or queueing writes, rather than showing or replaying one
/// account's data under another.
class OfflineLibraryCache {
  OfflineLibraryCache({
    required this.accountId,
    required this.store,
    required this.queue,
    required this.currentUserId,
    this.sync,
  });

  final String accountId;
  final OfflineStore store;
  final PendingWriteQueue queue;

  /// Drained before a read, so a fresh load never overwrites a change that
  /// hasn't reached the server yet. Null in tests that don't sync.
  SyncCoordinator? sync;

  /// The signed-in uid right now — compared with [accountId] by [isActive].
  final String? Function() currentUserId;

  static const _shelfKey = 'shelf_rows';
  static String _eventsKey(int year) => 'events_$year';

  List<Map<String, dynamic>>? _shelf;
  bool _shelfLoaded = false;
  final _events = <int, List<Map<String, dynamic>>?>{};

  /// Serializes every cache write, so two quick offline commands can't
  /// interleave a read-modify-write of the same document.
  ///
  /// Every link recovers from its own failure ([_logPersistFailure]): a
  /// chain that kept a failed write's error would skip every later write
  /// for the rest of the session and surface that old error from each one —
  /// failing library writes whose queued request had actually succeeded.
  Future<void> _chain = Future.value();

  static void _logPersistFailure(Object error, StackTrace stackTrace) {
    AppLogger.error(
      'OfflineLibraryCache',
      'Persisting the offline cache failed.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  bool get isActive => currentUserId() == accountId;

  /// Whether the app is known to be offline — a read should come from the
  /// cache rather than wait on a request that can only time out.
  bool get shouldQueue => isActive && ConnectivityController.isOffline.value;

  /// Whether a *write* must go into the queue rather than straight to the
  /// server: when offline, and also while earlier writes are still waiting.
  ///
  /// The second case is what keeps replay ordered. Right after reconnecting
  /// (or while a drain is stuck behind an unreachable write) a direct write
  /// would reach the server *before* the older queued ones — and then the
  /// replay of an older value to the same row would overwrite it, silently
  /// undoing the reader's newest change. Queued behind them, it lands last.
  Future<bool> mustQueueWrite() async {
    if (!isActive) return false;
    if (ConnectivityController.isOffline.value) return true;
    return !await queue.isEmpty;
  }

  /// Sends queued writes now if the server is believed reachable — called
  /// after a write was queued only to keep it behind older ones, so it
  /// doesn't wait for the next reconnect to go out.
  void syncSoon() {
    if (!isActive || ConnectivityController.isOffline.value) return;
    final coordinator = sync;
    if (coordinator != null) unawaited(coordinator.flush());
  }

  /// Drains pending writes if the server is reachable, then says whether
  /// any are still waiting — in which case a read must come from the cache,
  /// since the server doesn't have those changes yet. Never throws.
  Future<bool> drainBeforeRead() async {
    if (!isActive) return false;
    try {
      await sync?.flush();
      return !await queue.isEmpty;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'OfflineLibraryCache',
        'Draining before a read failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return !await queue.isEmpty;
    }
  }

  Future<void> enqueue(PendingWrite write) => queue.enqueue(write);

  String newWriteId() => queue.newId();

  // ---------------------------------------------------------------- shelf

  Future<List<Map<String, dynamic>>?> readShelf() async {
    if (!isActive) return null;
    if (!_shelfLoaded) {
      final raw = await store.read(_shelfKey);
      _shelf = raw is List ? [for (final row in raw) ?_asRow(row)] : null;
      _shelfLoaded = true;
    }
    final shelf = _shelf;
    return shelf == null
        ? null
        : [
            for (final row in shelf) {...row},
          ];
  }

  /// Replaces the cached shelf with a fresh server answer.
  Future<void> writeShelf(List<Map<String, dynamic>> rows) {
    if (!isActive) return Future.value();
    _shelf = [for (final row in rows) _deepCopy(row)];
    _shelfLoaded = true;
    return _persistShelf();
  }

  /// Adds [row] (a `user_books` row with its `book` embedded), replacing
  /// any cached row with the same id.
  Future<void> upsertShelfRow(Map<String, dynamic> row) async {
    final shelf = await readShelf();
    if (shelf == null) return;
    final id = row['id'];
    _shelf = [
      _deepCopy(row),
      for (final existing in shelf)
        if (existing['id'] != id) existing,
    ];
    await _persistShelf();
  }

  /// Merges a server-returned row (which may lack the embedded `book` and
  /// `owned_edition`) over the cached one, keeping the embeds.
  Future<void> mergeShelfRow(Map<String, dynamic> row) async {
    final shelf = await readShelf();
    if (shelf == null) return;
    final id = row['id'];
    _shelf = [
      for (final existing in shelf)
        if (existing['id'] == id) {...existing, ...row} else existing,
    ];
    await _persistShelf();
  }

  /// Applies [values] to the cached row [id] as the server would, and
  /// returns the patched row — null when that row isn't cached (so the
  /// write can't be represented offline).
  ///
  /// Mirrors what the `touch_updated_at` trigger does server-side, since
  /// the shelf's local order depends on it: any change other than a
  /// position-only one bumps `updated_at`, and a status or shelf change
  /// clears `shelf_position`. Sync then lets the real trigger decide.
  Future<Map<String, dynamic>?> patchShelfRow(
    String id,
    Map<String, Object?> values,
  ) async {
    final shelf = await readShelf();
    if (shelf == null) return null;
    Map<String, dynamic>? patched;
    _shelf = [
      for (final row in shelf)
        if (row['id'] == id) patched = _patch(row, values) else row,
    ];
    if (patched == null) return null;
    await _persistShelf();
    return {...patched};
  }

  static Map<String, dynamic> _patch(
    Map<String, dynamic> row,
    Map<String, Object?> values,
  ) {
    final next = {...row, ...values};
    final changesPlace =
        (values.containsKey('status') && values['status'] != row['status']) ||
        (values.containsKey('shelf_id') &&
            values['shelf_id'] != row['shelf_id']);
    if (changesPlace && !values.containsKey('shelf_position')) {
      next['shelf_position'] = null;
    }
    final positionOnly = values.keys.every((key) => key == 'shelf_position');
    if (!positionOnly) {
      next['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    // A different owned edition than the embedded one: drop the stale
    // embed (the book shows the work's own cover and pages) until a sync
    // brings the real one back.
    if (values.containsKey('owned_edition_id')) {
      final embedded = row['owned_edition'];
      final embeddedId = embedded is Map ? embedded['id'] : null;
      if (embeddedId != values['owned_edition_id']) {
        next['owned_edition'] = null;
      }
    }
    return next;
  }

  Future<void> removeShelfRow(String id) async {
    final shelf = await readShelf();
    if (shelf == null) return;
    _shelf = [
      for (final row in shelf)
        if (row['id'] != id) row,
    ];
    await _persistShelf();
  }

  /// `set_shelf_order`, locally: [orderedIds] take positions 0, 1, 2…
  Future<void> applyShelfOrder(List<String> orderedIds) async {
    final shelf = await readShelf();
    if (shelf == null) return;
    final positions = {
      for (final (i, id) in orderedIds.indexed) id: i.toDouble(),
    };
    _shelf = [
      for (final row in shelf)
        if (positions[row['id']] case final position?)
          {...row, 'shelf_position': position}
        else
          row,
    ];
    await _persistShelf();
  }

  Future<void> _persistShelf() {
    final snapshot = _shelf;
    return _chain = _chain
        .then((_) => store.write(_shelfKey, snapshot))
        .catchError(_logPersistFailure);
  }

  // --------------------------------------------------------------- events

  Future<List<Map<String, dynamic>>?> readEvents(int year) async {
    if (!isActive) return null;
    if (!_events.containsKey(year)) {
      final raw = await store.read(_eventsKey(year));
      _events[year] = raw is List
          ? [for (final row in raw) ?_asRow(row)]
          : null;
    }
    final rows = _events[year];
    return rows == null
        ? null
        : [
            for (final row in rows) {...row},
          ];
  }

  Future<void> writeEvents(int year, List<Map<String, dynamic>> rows) {
    if (!isActive) return Future.value();
    _events[year] = [for (final row in rows) _deepCopy(row)];
    return _persistEvents(year);
  }

  /// Adds one locally-made `reading_events` row to its year's cache —
  /// creating that year's cache if none was ever fetched, so an offline
  /// journal still shows what was logged offline.
  Future<void> appendEvent(Map<String, dynamic> row) async {
    if (!isActive) return;
    final occurredAt = DateTime.tryParse('${row['occurred_at']}');
    if (occurredAt == null) return;
    final year = occurredAt.toLocal().year;
    final rows = await readEvents(year) ?? [];
    _events[year] = [...rows, _deepCopy(row)];
    await _persistEvents(year);
  }

  Future<void> removeEventsForTitle(String title) async {
    if (!isActive) return;
    // The current year is the one a journal shows; make sure it's in
    // memory even if nothing has read it yet this session.
    await readEvents(DateTime.now().year);
    for (final year in _events.keys.toList()) {
      final rows = _events[year];
      if (rows == null) continue;
      _events[year] = [
        for (final row in rows)
          if (row['title'] != title) row,
      ];
      await _persistEvents(year);
    }
  }

  Future<void> _persistEvents(int year) {
    final snapshot = _events[year];
    return _chain = _chain
        .then((_) => store.write(_eventsKey(year), snapshot))
        .catchError(_logPersistFailure);
  }

  static Map<String, dynamic>? _asRow(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static Map<String, dynamic> _deepCopy(Map<String, dynamic> row) => {
    for (final MapEntry(:key, :value) in row.entries)
      key: value is Map ? Map<String, dynamic>.from(value) : value,
  };
}
