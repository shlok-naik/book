import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../diagnostics/app_logger.dart';
import '../network/connectivity_controller.dart';
import 'pending_write.dart';
import 'pending_write_queue.dart';

/// How one replayed write turned out.
enum ReplayOutcome {
  /// The server applied it.
  applied,

  /// The server couldn't be reached — stop, keep it, try again later.
  unreachable,

  /// The server answered and refused it (the row is gone, a constraint
  /// failed). Retrying the identical request can't help, so it's dropped.
  rejected,
}

/// Sends one [PendingWrite] to the backend. An interface so tests can
/// replay against a fake instead of Supabase.
abstract interface class PendingWriteExecutor {
  Future<ReplayOutcome> execute(PendingWrite write);
}

/// [PendingWriteExecutor] against the real Supabase client.
class SupabaseWriteExecutor implements PendingWriteExecutor {
  SupabaseWriteExecutor({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<ReplayOutcome> execute(PendingWrite write) async {
    try {
      final Future<Object?> request = switch (write) {
        PendingUpdate(:final table, :final rowId, :final values) =>
          _client.from(table).update(values).eq('id', rowId),
        PendingInsert(:final table, :final values) =>
          _client.from(table).insert(values),
        PendingDelete(:final table, :final column, :final value) =>
          _client.from(table).delete().eq(column, value),
        PendingRpc(:final function, :final params) => _client.rpc<Object?>(
          function,
          params: params,
        ),
      };
      await request.timeout(_timeout);
      return ReplayOutcome.applied;
    } on TimeoutException {
      return ReplayOutcome.unreachable;
    } on SocketException {
      return ReplayOutcome.unreachable;
    } on http.ClientException {
      return ReplayOutcome.unreachable;
    } on PostgrestException catch (error) {
      final code = int.tryParse(error.code ?? '');
      return code != null && code >= 500
          ? ReplayOutcome.unreachable
          : ReplayOutcome.rejected;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SupabaseWriteExecutor',
        'A queued write failed unexpectedly; dropping it.',
        error: error,
        stackTrace: stackTrace,
      );
      return ReplayOutcome.rejected;
    }
  }
}

/// Drains the [PendingWriteQueue] whenever the backend is reachable: at
/// startup, and every time [ConnectivityController.isOffline] turns false.
///
/// Replays strictly in order and stops at the first write that can't
/// reach the server, so nothing is ever applied out of sequence. A write
/// the server *refuses* is dropped (and counted in [lastRejected]) rather
/// than blocking everything behind it forever.
///
/// Once a drain has changed anything — applied or dropped a write — it
/// calls [onSynced], which the composition root points at a shelf reload:
/// the server's answer, triggers and all (`updated_at`, the shelf order
/// the database settled on, a rejected write's row as it really is), is
/// the truth from then on.
///
/// Conflicts resolve as last-write-wins: a change queued here overwrites
/// whatever another device wrote to the same row in the meantime.
class SyncCoordinator {
  SyncCoordinator({required this.queue, required this.executor, this.onSynced});

  final PendingWriteQueue queue;
  final PendingWriteExecutor executor;

  /// Called after a drain that applied or dropped at least one write.
  Future<void> Function()? onSynced;

  /// True while a drain is running — the indicator shows "syncing".
  final ValueNotifier<bool> isSyncing = ValueNotifier(false);

  /// How many writes the last drain had to drop because the server refused
  /// them. Surfaced so the reader is told rather than left wondering why a
  /// change didn't stick.
  final ValueNotifier<int> lastRejected = ValueNotifier(0);

  Future<void>? _running;
  bool _started = false;

  /// Starts draining on reconnect, and drains once now. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    ConnectivityController.isOffline.addListener(_onConnectivityChanged);
    unawaited(flush());
  }

  void dispose() {
    ConnectivityController.isOffline.removeListener(_onConnectivityChanged);
  }

  void _onConnectivityChanged() {
    if (!ConnectivityController.isOffline.value) unawaited(flush());
  }

  /// Drains the queue now. Concurrent callers share one drain. Never
  /// throws.
  ///
  /// [onSynced] runs only after the drain has fully finished and released
  /// [flush] — not inside it. It reloads the shelf, and a shelf load drains
  /// before it reads (`OfflineLibraryCache.drainBeforeRead`); calling it
  /// from inside the running drain would have that load wait on the very
  /// drain waiting on it.
  Future<void> flush() {
    return _running ??= () async {
      var changed = false;
      try {
        changed = await _drain();
      } on Object catch (error, stackTrace) {
        // The queue's own storage failing (not a write being refused —
        // that's an outcome). Logged; the queue is retried on the next
        // flush, and callers that fire this unawaited never see a throw.
        AppLogger.error(
          'SyncCoordinator',
          'Draining the write queue failed.',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        _running = null;
      }
      if (changed) unawaited(_notifySynced());
    }();
  }

  Future<void> _notifySynced() async {
    try {
      await onSynced?.call();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SyncCoordinator',
        'Reloading after a sync failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Returns whether anything was applied or dropped.
  ///
  /// Keeps going until the queue is empty, not just through the writes that
  /// were there when it started: a write queued *during* a drain (writes
  /// queue behind older ones while any are waiting — see
  /// `OfflineLibraryCache.mustQueueWrite`) would otherwise sit until the
  /// next reconnect, and a concurrent [flush] joins this drain rather than
  /// starting its own. Every pass removes each write it looks at, so this
  /// always ends.
  Future<bool> _drain() async {
    if (ConnectivityController.isOffline.value) return false;
    var writes = await queue.snapshot();
    if (writes.isEmpty) return false;

    isSyncing.value = true;
    var changed = false;
    var rejected = 0;
    try {
      while (writes.isNotEmpty) {
        for (final write in writes) {
          final outcome = await executor.execute(write);
          switch (outcome) {
            case ReplayOutcome.applied:
              await queue.remove(write.id);
              changed = true;
            case ReplayOutcome.rejected:
              AppLogger.warning(
                'SyncCoordinator',
                'The server refused a queued ${write.runtimeType}; dropped it.',
              );
              await queue.remove(write.id);
              rejected++;
              changed = true;
            case ReplayOutcome.unreachable:
              ConnectivityController.reportUnreachable();
              return changed;
          }
        }
        writes = await queue.snapshot();
      }
      ConnectivityController.reportReachable();
      return changed;
    } finally {
      isSyncing.value = false;
      if (changed) lastRejected.value = rejected;
    }
  }
}
