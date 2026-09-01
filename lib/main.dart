import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/analytics/app_analytics.dart';
import 'core/diagnostics/app_logger.dart';
import 'core/diagnostics/crash_reporter.dart';
import 'core/env/env.dart';
import 'core/purchases/purchases_service.dart';
import 'core/supabase/supabase_service.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/startup_failure_page.dart';
import 'features/library/data/book_cache_repository.dart';
import 'features/library/data/google_books_api_client.dart';
import 'features/library/data/reading_event_repository.dart';
import 'features/library/data/user_book_repository.dart';
import 'features/library/domain/book_lookup_service.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/library/presentation/library_scope.dart';
import 'features/memory/presentation/controllers/memory_controller.dart';
import 'features/memory/presentation/memory_scope.dart';
import 'features/onboarding/data/onboarding_profile_repository.dart';
import 'features/onboarding/data/session_service.dart';
import 'features/onboarding/presentation/pages/welcome_page.dart';
import 'features/shell/presentation/pages/root_shell.dart';

Future<void> main() async {
  // Everything runs inside one guarded zone so an async error raised
  // outside a Flutter callback — a stray `Future` in a repository, say —
  // reaches [AppLogger] rather than the console alone. Combined with the
  // two handlers below, no failure anywhere in the app escapes
  // unreported once a crash-reporting sink is attached.
  runZonedGuarded(_bootstrap, (error, stackTrace) {
    AppLogger.error(
      'main',
      'Uncaught asynchronous error.',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    AppLogger.error(
      'FlutterError',
      details.summary.toString(),
      error: details.exception,
      stackTrace: details.stack,
    );
    // Keep the red-screen/console behaviour developers rely on; the
    // handler above is additive, not a replacement.
    FlutterError.presentError(details);
  };

  // Errors from the engine itself (platform channels, gesture
  // dispatch) that never pass through FlutterError.
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'PlatformDispatcher',
      'Uncaught platform error.',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };

  // `.env` is a development convenience, never a release dependency —
  // it ships as a readable asset, so [Env] ignores it outright in
  // release and there is nothing to load. See [Env] for the whole rule.
  if (Env.isDotEnvFallbackAvailable) {
    try {
      await dotenv.load(fileName: '.env');
    } on Object catch (error) {
      AppLogger.info(
        'main',
        'No .env file loaded ($error); using --dart-define.',
      );
    }
  }

  // Attached before anything that can fail, so a crash during the rest
  // of startup is itself reported. Never awaited for its own sake — see
  // [CrashReporter.attach] on why a telemetry failure must not stop the
  // app from starting.
  // Analytics rides on the same Firebase app the crash reporter
  // initializes, so it only attaches once that has actually succeeded.
  if (await CrashReporter.attach()) AppAnalytics.attach();

  final missing = Env.missingKeys;
  if (missing.isNotEmpty) {
    // A misconfigured build fails here, once, with the list of what is
    // missing — rather than at whichever screen first happens to touch
    // one of these and throwing an opaque StateError at the reader.
    AppLogger.error('main', 'Missing configuration: ${missing.join(', ')}.');
    runApp(StartupFailureApp(missingKeys: missing));
    return;
  }

  try {
    await SupabaseService.init();
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'main',
      'Supabase failed to initialize.',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(const StartupFailureApp(missingKeys: []));
    return;
  }

  // Purchases are not load-bearing for launch: a reader whose
  // RevenueCat configuration fails should still get their library, just
  // without entitlement state. Previously this could take the whole
  // startup down.
  try {
    await PurchasesService.configure();
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'main',
      'RevenueCat failed to configure; continuing without entitlements.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // A reader who already has a session from a previous launch should
  // resolve to the same RevenueCat identity they purchased under, not a
  // fresh anonymous one — sign-in/sign-up call this again themselves
  // once a session is created mid-flow (see `SessionService`). Fire-
  // and-forget: this must never hold up startup waiting on it.
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId != null) {
    CrashReporter.identify(userId);
    AppAnalytics.identify(userId);
    reportingFailure(
      const PurchasesService().identify(userId),
      source: 'main',
      message: 'Could not restore the RevenueCat identity at startup.',
    );
  }

  // Portrait only. Every screen is laid out for one portrait column, and
  // the streaks page fits a whole year without scrolling — in landscape
  // it has nowhere to put December. Also declared in the Android
  // manifest and the iOS plist, so the OS never even offers the rotation
  // animation; this covers the case where those are bypassed (an
  // already-running app during development, mainly).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Android 15 draws every app edge-to-edge whether it asks to or not,
  // so ask — opting in means the insets are correct now rather than the
  // floating tab bar ending up under the gesture handle later. Every
  // page already wraps its content in a SafeArea.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const BookApp());
}

class BookApp extends StatefulWidget {
  const BookApp({
    super.key,
    this.libraryController,
    this.memoryController,
    this.sessionService,
    this.profileRepository,
    this.alwaysShowOnboarding = false,
  });

  /// Injection point for tests: pass a controller backed by fakes to
  /// drive the library without Supabase or Google Books. In the app this
  /// is null and the real graph below is composed instead.
  final LibraryController? libraryController;

  /// Injection point for tests: pass a controller backed by a fake
  /// repository instead of a real Supabase call. In the app this is
  /// null and a real one is built instead.
  final MemoryController? memoryController;

  /// Injection point for tests: pass a fake to control whether a session
  /// exists (and how signing in behaves) without a real Supabase call.
  /// In the app this is null and a real one, backed by the initialized
  /// Supabase client, is built instead.
  final SessionService? sessionService;

  /// Injection point for tests: pass a fake to control what onboarding's
  /// profile save/averages calls do without a real Supabase call. In
  /// the app this is null and a real one is built instead.
  final OnboardingProfileRepository? profileRepository;

  /// When true, ignores an existing session and always starts at
  /// [WelcomePage].
  final bool alwaysShowOnboarding;

  @override
  State<BookApp> createState() => _BookAppState();
}

class _BookAppState extends State<BookApp> {
  /// The app's only composition root for the library feature: clients
  /// and repositories are built here once and injected downward, so no
  /// widget constructs its own (see CLAUDE.md § Dependency Injection).
  late final LibraryController _library =
      widget.libraryController ?? _buildLibraryController();

  late final MemoryController _memory =
      widget.memoryController ?? MemoryController();

  late final SessionService _session =
      widget.sessionService ?? SessionService();

  late final OnboardingProfileRepository _profiles =
      widget.profileRepository ?? OnboardingProfileRepository();

  /// Whether the log-in gate has already been cleared. Read once at
  /// startup — [WelcomePage] and the sign in/up screens each replace the
  /// whole navigation stack with [RootShell] on success (see their
  /// `pushAndRemoveUntil` calls) rather than flipping this flag, so it
  /// only has to reflect "was there already a session when the app
  /// launched", not track changes afterward.
  late final bool _signedIn = _session.isSignedIn;

  /// Owned only when we built it — an injected client belongs to the
  /// caller, so we must not close it.
  GoogleBooksApiClient? _ownedGoogleBooks;

  LibraryController _buildLibraryController() {
    final googleBooks = GoogleBooksApiClient();
    _ownedGoogleBooks = googleBooks;

    return LibraryController(
      lookup: BookLookupService(
        cache: BookCacheRepository(),
        googleBooks: googleBooks,
      ),
      userBooks: UserBookRepository(),
      events: ReadingEventRepository(),
    );
  }

  @override
  void dispose() {
    _ownedGoogleBooks?.dispose();
    if (widget.libraryController == null) _library.dispose();
    if (widget.memoryController == null) _memory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        // The status bar sits over the app's own background, so its
        // icons have to contrast with *that* — with the app forced to
        // light while the phone is in dark mode, the system's own choice
        // would render them invisible.
        final isDark =
            themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: LibraryScope(
            controller: _library,
            child: MemoryScope(
              controller: _memory,
              child: MaterialApp(
                title: 'cactus',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                scrollBehavior: AppScrollBehavior(),
                // Screen views come from each route's own name rather than
                // a line in every page's initState — see [AppAnalytics].
                navigatorObservers: AppAnalytics.navigatorObservers,
                home: (_signedIn && !widget.alwaysShowOnboarding)
                    ? const RootShell()
                    : WelcomePage(session: _session, profiles: _profiles),
              ),
            ),
          ),
        );
      },
    );
  }
}
