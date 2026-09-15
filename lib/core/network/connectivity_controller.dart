import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../diagnostics/app_logger.dart';
import '../env/env.dart';

/// Whether the app can currently reach its backend — what the offline
/// indicator in every page header shows, and what decides whether a
/// shelf write goes straight to Supabase or into the pending-write queue
/// (see `SyncCoordinator`).
///
/// Three signals feed one answer, because none is trustworthy alone:
///
/// * **the OS network state** (`connectivity_plus`) — instant, but only
///   says an interface is up, not that anything is reachable through it
///   (a captive portal, a dead router). "No interface at all" is taken at
///   its word; anything else triggers…
/// * **a reachability probe** — one small request to Supabase's health
///   endpoint. Any HTTP answer, even an error status, means reachable;
///   only a transport failure or a timeout means offline.
/// * **real requests failing** — `runSupabase` reports a transport failure
///   via [reportUnreachable] (which probes rather than trusting one failed
///   call) and a success via [reportReachable].
///
/// While offline it re-probes on a timer, so reconnection is noticed even
/// on a network change the OS doesn't announce.
///
/// Inert until [attach] runs — `_bootstrap` calls it; widget tests never
/// run `main`, so there [isOffline] simply stays false and every report is
/// a no-op, the same rule `CrashReporter` follows.
class ConnectivityController {
  ConnectivityController._();

  /// True while the backend is believed unreachable.
  static final ValueNotifier<bool> isOffline = ValueNotifier(false);

  static const _probeTimeout = Duration(seconds: 5);
  static const _retryWhileOffline = Duration(seconds: 20);

  static bool _attached = false;
  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _retryTimer;
  static Future<bool>? _probeInFlight;
  static Future<bool> Function() _probe = _probeSupabase;

  static bool get isAttached => _attached;

  /// Starts watching. Never throws — a platform channel that fails just
  /// leaves the app relying on probes and request failures.
  static Future<void> attach({
    Connectivity? connectivity,
    @visibleForTesting Future<bool> Function()? probe,
  }) async {
    if (_attached) return;
    _attached = true;
    if (probe != null) _probe = probe;
    final source = connectivity ?? Connectivity();
    try {
      _subscription = source.onConnectivityChanged.listen(
        _onNetworkChanged,
        onError: (Object error, StackTrace stackTrace) => AppLogger.error(
          'ConnectivityController',
          'The network state stream failed.',
          error: error,
          stackTrace: stackTrace,
        ),
      );
      _onNetworkChanged(await source.checkConnectivity());
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ConnectivityController',
        'Could not read the network state; relying on probes.',
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(recheck());
    }
  }

  /// A request just failed at the transport level. One failure isn't proof
  /// (a flaky request, a slow endpoint), so this probes before deciding.
  static void reportUnreachable() {
    if (!_attached) return;
    unawaited(recheck());
  }

  /// A request just succeeded — whatever the last probe said, the backend
  /// is reachable right now.
  static void reportReachable() {
    if (!_attached || !isOffline.value) return;
    _setOffline(false);
  }

  /// Probes now and updates [isOffline]; returns whether it's reachable.
  /// Concurrent callers share one probe.
  static Future<bool> recheck() {
    return _probeInFlight ??= () async {
      try {
        final reachable = await _probe();
        _setOffline(!reachable);
        return reachable;
      } finally {
        _probeInFlight = null;
      }
    }();
  }

  static void _onNetworkChanged(List<ConnectivityResult> results) {
    final noInterface =
        results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
    if (noInterface) {
      _setOffline(true);
    } else {
      unawaited(recheck());
    }
  }

  static void _setOffline(bool offline) {
    if (offline) {
      _retryTimer ??= Timer.periodic(_retryWhileOffline, (_) {
        unawaited(recheck());
      });
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    if (isOffline.value == offline) return;
    AppLogger.info(
      'ConnectivityController',
      offline ? 'Backend unreachable; working offline.' : 'Back online.',
    );
    isOffline.value = offline;
  }

  /// Any HTTP response from the auth health endpoint counts as reachable.
  static Future<bool> _probeSupabase() async {
    try {
      final uri = Uri.parse('${Env.supabaseUrl}/auth/v1/health');
      await http
          .get(uri, headers: {'apikey': Env.supabaseAnonKey})
          .timeout(_probeTimeout);
      return true;
    } on Object {
      return false;
    }
  }

  /// Test-only: detaches and returns to the inert, online state.
  @visibleForTesting
  static Future<void> reset() async {
    await _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _probeInFlight = null;
    _probe = _probeSupabase;
    _attached = false;
    isOffline.value = false;
  }

  /// Test-only: forces the state without a probe, as if [attach] had run
  /// and concluded [offline]. Starts no retry timer — a forced state has
  /// nothing real to re-probe, and a pending timer would fail a widget
  /// test's end-of-test invariants.
  @visibleForTesting
  static void debugSetOffline(bool offline) {
    _attached = true;
    _setOffline(offline);
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}
