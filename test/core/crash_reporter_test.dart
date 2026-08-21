import 'package:book/core/diagnostics/app_logger.dart';
import 'package:book/core/diagnostics/crash_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// `FirebaseCrashlytics.instance` throws synchronously when Firebase was
/// never initialized, so every entry point on [CrashReporter] has to be
/// inert until [CrashReporter.attach] has succeeded. Widget tests build
/// the app directly and never run `main`, which makes that the normal
/// state here rather than an edge case — and makes this the test that
/// would catch a guard being dropped.
void main() {
  test('is not attached in a test binding', () {
    expect(CrashReporter.isAttached, isFalse);
  });

  test('identify is a no-op rather than a throw when unattached', () {
    expect(() => CrashReporter.identify('some-user-id'), returnsNormally);
    expect(() => CrashReporter.identify(null), returnsNormally);
  });

  test('logging still works with no sink attached', () {
    AppLogger.emitToConsole = false;
    addTearDown(() => AppLogger.emitToConsole = true);

    expect(
      () => AppLogger.error('test', 'boom', error: StateError('boom')),
      returnsNormally,
    );
  });

  test('a sink that throws never reaches the caller', () {
    AppLogger.emitToConsole = false;
    AppLogger.sink = (_) => throw StateError('the crash reporter is down');
    addTearDown(() {
      AppLogger.sink = null;
      AppLogger.emitToConsole = true;
    });

    // A broken crash reporter must never become the thing that crashes
    // the app.
    expect(() => AppLogger.warning('test', 'still fine'), returnsNormally);
  });
}
