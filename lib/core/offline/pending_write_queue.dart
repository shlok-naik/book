import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'offline_store.dart';
import 'pending_write.dart';

/// The ordered list of writes made while offline, persisted through an
/// [OfflineStore] so a write survives the app being closed before the
/// connection comes back. `SyncCoordinator` drains it.
///
/// Order is the whole contract: writes are replayed first-in, first-out,
/// because a later write to the same row must win.
class PendingWriteQueue {
  PendingWriteQueue({required this.store});

  static const _key = 'pending_writes';

  final OfflineStore store;
  List<PendingWrite> _writes = const [];
  Future<void>? _loaded;

  /// How many writes are waiting — the offline indicator's "N changes will
  /// sync" and its syncing state.
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  final _random = Random();

  /// Reads the persisted queue once. Every other method awaits this, so
  /// callers never need to.
  Future<void> load() => _loaded ??= () async {
    final raw = await store.read(_key);
    _writes = [
      if (raw is List)
        for (final entry in raw) ?PendingWrite.fromJson(entry),
    ];
    pendingCount.value = _writes.length;
  }();

  Future<List<PendingWrite>> snapshot() async {
    await load();
    return List.unmodifiable(_writes);
  }

  Future<bool> get isEmpty async {
    await load();
    return _writes.isEmpty;
  }

  /// A fresh id for a write about to be enqueued.
  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  /// Appends [write]. An update to the same row as the queue's *last* entry
  /// is merged into it instead — a reader nudging a page number up five
  /// times offline sends one request, not five. Only the last entry, so
  /// merging can never reorder a write past something that happened
  /// between the two.
  Future<void> enqueue(PendingWrite write) async {
    await load();
    final last = _writes.isEmpty ? null : _writes.last;
    if (write is PendingUpdate &&
        last is PendingUpdate &&
        last.table == write.table &&
        last.rowId == write.rowId) {
      _writes = [..._writes.take(_writes.length - 1), last.mergedWith(write)];
    } else {
      _writes = [..._writes, write];
    }
    await _persist();
  }

  /// Removes the entry with [id] — once it has synced, or been rejected.
  Future<void> remove(String id) async {
    await load();
    _writes = [
      for (final write in _writes)
        if (write.id != id) write,
    ];
    await _persist();
  }

  /// Drops everything — the account this queue belonged to is gone (its
  /// library was replaced when an email was linked).
  Future<void> clear() async {
    await load();
    _writes = const [];
    await _persist();
  }

  Future<void> _persist() async {
    pendingCount.value = _writes.length;
    await store.write(_key, [for (final write in _writes) write.toJson()]);
  }
}
