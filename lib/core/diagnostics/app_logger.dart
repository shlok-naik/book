import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// How bad a [AppLogger] record is. Ordered, so a future sink can filter
/// on `index >=` rather than matching each value.
enum LogLevel {
  debug(500, 'DEBUG'),
  info(800, 'INFO'),
  warning(900, 'WARN'),
  error(1000, 'ERROR');

  const LogLevel(this.value, this.label);

  /// `dart:developer`'s level scale, which matches `package:logging`'s.
  final int value;
  final String label;
}

/// One logged event, in the shape a crash reporter wants.
class LogRecord {
  const LogRecord({
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;

  /// Where it came from — a class or subsystem name, e.g.
  /// `LibraryController`.
  final String source;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

/// The app's one logging seam.
///
/// Two reasons this exists rather than `debugPrint`:
///
/// * `debugPrint` is compiled out of release builds, so every diagnostic
///   the app has ever written has been invisible in exactly the builds
///   where something going wrong actually matters. `dart:developer`'s
///   `log` survives release and carries structure (level, source, error,
///   stack) instead of a flattened string.
/// * A single choke point is what a crash reporter needs. Point [sink]
///   at Sentry/Crashlytics in `main` and every warning and error in the
///   app starts being reported, without a single call site changing.
///
/// Deliberately not an interface with an injected instance: logging is
/// ambient, and threading a logger through every constructor would buy
/// nothing that [sink] doesn't.
abstract final class AppLogger {
  /// Where records go in addition to the local developer log. Null by
  /// default — set it once, at startup, before anything else runs.
  ///
  /// A throwing sink is swallowed: a broken crash reporter must never
  /// become the thing that crashes the app.
  static void Function(LogRecord record)? sink;

  /// Set false in tests that assert on stderr, or that deliberately
  /// exercise failure paths and would otherwise drown the run in noise.
  static bool emitToConsole = true;

  static void debug(String source, String message) =>
      _log(LogLevel.debug, source, message);

  static void info(String source, String message) =>
      _log(LogLevel.info, source, message);

  /// Something recoverable went wrong — a fire-and-forget write that
  /// failed, a degraded fallback taken.
  static void warning(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _log(
    LogLevel.warning,
    source,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  /// Something the reader will have noticed.
  static void error(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _log(
    LogLevel.error,
    source,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  static void _log(
    LogLevel level,
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (emitToConsole) {
      developer.log(
        message,
        name: source,
        level: level.value,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final reporter = sink;
    if (reporter == null) return;
    try {
      reporter(
        LogRecord(
          level: level,
          source: source,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } on Object catch (sinkError, sinkStack) {
      if (kDebugMode) {
        developer.log(
          'AppLogger sink threw and was ignored',
          name: 'AppLogger',
          level: LogLevel.error.value,
          error: sinkError,
          stackTrace: sinkStack,
        );
      }
    }
  }
}

/// Runs [future] for its side effect, reporting a failure instead of
/// letting it surface as an unhandled async error.
///
/// This is the honest version of `unawaited(x.catchError((_) {}))`,
/// which the app used in several places: same "must not affect the
/// caller" behaviour, except the failure is actually recorded rather
/// than silently dropped. Use it for genuinely optional work — writing a
/// streak event, telling RevenueCat who the reader is — never for
/// anything the reader is waiting on.
void reportingFailure(
  Future<void> future, {
  required String source,
  required String message,
}) {
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      AppLogger.warning(source, message, error: error, stackTrace: stackTrace);
    }),
  );
}
