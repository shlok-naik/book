import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'app_logger.dart';

/// Sends [AppLogger]'s warnings and errors to Firebase Crashlytics.
///
/// The app already routes every failure it knows about through
/// [AppLogger] — `FlutterError.onError`, `PlatformDispatcher.onError` and
/// the guarded zone in `main`, plus every `reportingFailure(...)` call
/// and every controller that catches a repository exception. So this
/// attaches in exactly one place, [AppLogger.sink], and every existing
/// call site starts reporting without changing.
///
/// **Do not also assign `FirebaseCrashlytics.instance.recordFlutterFatalError`
/// to `FlutterError.onError`**, which is what Firebase's own setup guide
/// tells you to do. `main` owns those handlers and already forwards them
/// here; adding Firebase's would report every framework error twice and
/// make the crash-free-users number quietly wrong.
abstract final class CrashReporter {
  /// Whether [attach] succeeded. Everything below no-ops until it has,
  /// because `FirebaseCrashlytics.instance` throws *synchronously* when
  /// Firebase was never initialized — so an unguarded call would not
  /// merely fail to report, it would take out whatever called it. That
  /// covers two real cases: a startup where Firebase itself failed, and
  /// widget tests, which build the app directly and never run `main`.
  static bool _attached = false;

  static bool get isAttached => _attached;

  /// Initializes Firebase and points [AppLogger.sink] at Crashlytics.
  ///
  /// Returns whether it worked. A failure here is not fatal and must not
  /// be: crash reporting is diagnostics, and an app that refuses to start
  /// because its telemetry is unreachable has turned a monitoring outage
  /// into an outage. The failure is logged locally instead.
  static Future<bool> attach() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'CrashReporter',
        'Firebase failed to initialize; crash reporting is off.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }

    final crashlytics = FirebaseCrashlytics.instance;

    // Debug runs would otherwise fill the console with real crash
    // reports from deliberately broken code. Set this to true
    // temporarily when you need to verify the pipeline end to end.
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    AppLogger.sink = (record) {
      // Debug and info are breadcrumbs, not incidents. Sending them
      // would cost quota and bury the reports that matter.
      if (record.level.index < LogLevel.warning.index) return;

      crashlytics.recordError(
        // A logged failure usually carries the real exception; when it
        // does not, the message is the most specific thing there is.
        record.error ?? record.message,
        record.stackTrace,
        reason: '${record.source}: ${record.message}',
        // `fatal` is what feeds the crash-free-users metric. An error is
        // something the reader noticed; a warning is a fire-and-forget
        // write that failed behind their back. Only the first should
        // count against a release.
        fatal: record.level == LogLevel.error,
      );
    };

    _attached = true;
    return true;
  }

  /// Ties subsequent reports to a reader, so a crash can be matched to
  /// the account that hit it — and to nothing else. The Supabase user id
  /// is an opaque UUID: enough to correlate reports from one person,
  /// never enough to identify them. Deliberately not the email address.
  ///
  /// Call on sign-in, and with null on sign-out.
  static void identify(String? userId) {
    if (!_attached) return;
    reportingFailure(
      FirebaseCrashlytics.instance.setUserIdentifier(userId ?? ''),
      source: 'CrashReporter',
      message: 'Could not set the Crashlytics user identifier.',
    );
  }
}
