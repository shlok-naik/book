import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/analytics/app_analytics.dart';
import 'core/auth/session_scope.dart';
import 'core/auth/session_service.dart';
import 'core/diagnostics/app_logger.dart';
import 'core/diagnostics/crash_reporter.dart';
import 'core/env/env.dart';
import 'core/network/connectivity_controller.dart';
import 'core/offline/offline_store.dart';
import 'core/offline/pending_write_queue.dart';
import 'core/offline/sync_coordinator.dart';
import 'core/offline/sync_scope.dart';
import 'core/platform/app_icon_controller.dart';
import 'core/platform/device_name.dart';
import 'core/purchases/plan_controller.dart';
import 'core/purchases/purchases_service.dart';
import 'core/supabase/supabase_service.dart';
import 'core/theme/app_color_theme.dart';
import 'core/theme/app_color_theme_controller.dart';
import 'core/theme/app_font_theme.dart';
import 'core/theme/app_font_theme_controller.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/bundled_fonts.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/startup_failure_page.dart';
import 'features/goals/presentation/controllers/goal_controller.dart';
import 'features/goals/presentation/goal_scope.dart';
import 'features/library/data/book_cache_repository.dart';
import 'features/library/data/book_details_repository.dart';
import 'features/library/data/book_notes_repository.dart';
import 'features/library/data/google_books_api_client.dart';
import 'features/library/data/offline_library_cache.dart';
import 'features/library/data/reading_event_repository.dart';
import 'features/library/data/user_book_repository.dart';
import 'features/library/domain/book_details_service.dart';
import 'features/library/domain/book_lookup_service.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/library/presentation/library_scope.dart';
import 'features/library/presentation/series_tile_style_controller.dart';
import 'features/logging/presentation/parser_mode_controller.dart';
import 'features/memory/presentation/controllers/memory_controller.dart';
import 'features/memory/presentation/memory_scope.dart';
import 'features/onboarding/data/onboarding_store.dart';
import 'features/onboarding/presentation/pages/welcome_page.dart';
import 'features/search/presentation/reading_tastes_controller.dart';
import 'features/settings/data/profile_repository.dart';
import 'features/shell/presentation/pages/root_shell.dart';
import 'features/shell/presentation/start_page_controller.dart';

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
  // Fonts ship with the app; never download one (see [BundledFonts]).
  BundledFonts.configure();

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

  // The app has no sign-up step, and every feature reads through RLS on
  // `auth.uid()` — so a session has to exist before the first frame, or
  // a fresh install renders an empty shelf that looks broken rather than
  // new. A reader who already has one (from a previous launch, or an
  // email they linked in settings) keeps it; only a first launch creates
  // anything. This is the one startup step with no graceful degradation:
  // there is no useful app without a session, so a failure here is a
  // startup failure rather than something to carry on past.
  try {
    await SessionService().ensureSession();
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'main',
      'Could not open a session.',
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
  var purchasesConfigured = false;
  try {
    await PurchasesService.configure();
    purchasesConfigured = true;
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'main',
      'RevenueCat failed to configure; continuing without entitlements.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Ties the session opened above — anonymous or email-linked, the uid
  // is the same either way — to the RevenueCat purchaser it bought
  // under, so entitlements resolve to the right account rather than a
  // fresh one. Fire-and-forget: this must never hold up startup.
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId != null) {
    CrashReporter.identify(userId);
    AppAnalytics.identify(userId);
    if (purchasesConfigured) {
      // Identify first, then read the entitlement: reading it before
      // `logIn` lands would ask about the anonymous RevenueCat id rather
      // than the purchaser this uid bought under. Both fire-and-forget —
      // the stream inside `attach` corrects the plan whenever the store
      // answers, so neither may hold up the first frame.
      reportingFailure(
        const PurchasesService()
            .identify(userId)
            .whenComplete(
              () => PlanController.attach(const PurchasesService()),
            ),
        source: 'main',
        message: 'Could not restore the RevenueCat identity at startup.',
      );
    }
    reportingFailure(
      DeviceName.current().then(
        (name) =>
            const ProfileRepository().recordDevice(userId, deviceName: name),
      ),
      source: 'main',
      message: 'Could not record this device on the profile.',
    );
  }

  // Watching the network is what lets every page header show an offline
  // mark and lets shelf writes queue instead of failing (see
  // [ConnectivityController]). Fire-and-forget: the first probe can take a
  // few seconds, and a load that starts before it answers simply falls back
  // to the offline cache when its own request fails.
  unawaited(ConnectivityController.attach());

  // Everything below is independent and none of it throws, so it runs
  // concurrently rather than as five sequential round trips to the
  // platform before the first frame.
  //
  // * Portrait only. Every screen is laid out for one portrait column, and
  //   the streaks page fits a whole year without scrolling — in landscape
  //   it has nowhere to put December. Also declared in the Android manifest
  //   and the iOS plist, so the OS never even offers the rotation
  //   animation; this covers the case where those are bypassed (an
  //   already-running app during development, mainly).
  // * Android 15 draws every app edge-to-edge whether it asks to or not, so
  //   ask — opting in means the insets are correct now rather than the
  //   floating tab bar ending up under the gesture handle later. Every page
  //   already wraps its content in a SafeArea.
  // * The onboarding flag is read before the first frame so the app opens
  //   on the right screen rather than flashing one and replacing it. Note
  //   this is *not* "is the reader signed in" — they always are by now,
  //   anonymously — it is "have they been shown around yet". See
  //   [OnboardingStore].
  // * The icon, accent and fonts aren't load-bearing — a failure just leaves
  //   the defaults — but reading them first avoids a flash of the wrong
  //   accent.
  final (_, _, introSeen, _, _, _, _, _) = await (
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    const OnboardingStore().hasSeen(),
    AppIconController.initialize(),
    AppColorThemeController.initialize(),
    AppFontThemeController.initialize(),
    SeriesTileStyleController.initialize(),
    Future.wait([
      StartPageController.initialize(),
      ParserModeController.initialize(),
      ReadingTastesController.initialize(),
    ]),
  ).wait;

  runApp(BookApp(showOnboarding: !introSeen));
}

class BookApp extends StatefulWidget {
  const BookApp({
    super.key,
    this.libraryController,
    this.memoryController,
    this.sessionService,
    this.goalController,
    this.showOnboarding = false,
  });

  /// Injection point for tests: pass a controller backed by fakes to
  /// drive the library without Supabase or Google Books. In the app this
  /// is null and the real graph below is composed instead.
  final LibraryController? libraryController;

  /// Injection point for tests: pass a controller backed by a fake
  /// repository instead of a real Supabase call. In the app this is
  /// null and a real one is built instead.
  final MemoryController? memoryController;

  /// Injection point for tests: pass a fake so the settings account
  /// section can be driven without a real Supabase call. In the app this
  /// is null and a real one, backed by the initialized Supabase client,
  /// is built instead.
  final SessionService? sessionService;

  /// Injection point for tests: a controller backed by a fake repository.
  /// Null in the app, where a real one is built and loaded at startup.
  final GoalController? goalController;

  /// Whether to open on the intro rather than the app. Set by
  /// `_bootstrap` from [OnboardingStore] — true only on a fresh install.
  /// Defaults to false so a test gets the app itself without having to
  /// say so.
  final bool showOnboarding;

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

  late final GoalController _goal = widget.goalController ?? GoalController();

  @override
  void initState() {
    super.initState();
    // Fetched once up front: the add tab shows progress against it on the
    // very first frame a reader sees. Its own failure state is what the
    // stats page offers a retry for.
    if (widget.goalController == null) unawaited(_goal.load());
  }

  /// Owned only when we built it — an injected client belongs to the
  /// caller, so we must not close it.
  GoogleBooksApiClient? _ownedGoogleBooks;

  /// The offline layer — a per-account cache and write queue, and the
  /// coordinator that drains it. Only built alongside the real library
  /// graph (an injected test controller has no Supabase behind it to sync
  /// with) and only for a signed-in uid, which `_bootstrap` guarantees.
  ({OfflineLibraryCache cache, PendingWriteQueue queue, SyncCoordinator sync})?
  _offline;

  ({OfflineLibraryCache cache, PendingWriteQueue queue, SyncCoordinator sync})?
  _buildOffline() {
    final String? userId;
    try {
      userId = Supabase.instance.client.auth.currentUser?.id;
    } on Object {
      return null;
    }
    if (userId == null) return null;

    final store = FileOfflineStore(accountId: userId);
    final queue = PendingWriteQueue(store: store);
    final sync = SyncCoordinator(
      queue: queue,
      executor: SupabaseWriteExecutor(),
    );
    final cache = OfflineLibraryCache(
      accountId: userId,
      store: store,
      queue: queue,
      sync: sync,
      currentUserId: () => Supabase.instance.client.auth.currentUser?.id,
    );
    return (cache: cache, queue: queue, sync: sync);
  }

  LibraryController _buildLibraryController() {
    final googleBooks = GoogleBooksApiClient();
    _ownedGoogleBooks = googleBooks;
    final offline = _offline = _buildOffline();

    final controller = LibraryController(
      lookup: BookLookupService(
        cache: BookCacheRepository(),
        googleBooks: googleBooks,
      ),
      userBooks: UserBookRepository(offline: offline?.cache),
      events: ReadingEventRepository(offline: offline?.cache),
      notes: BookNotesRepository(),
      // Shares the one Google Books client with the title lookup above, so
      // there is a single HTTP client to dispose.
      details: BookDetailsService(
        cache: BookDetailsRepository(),
        googleBooks: googleBooks,
      ),
    );

    if (offline != null) {
      // Once queued writes reach the server, its answer (triggers and all)
      // is the truth again — reload rather than trusting the local patches.
      offline.sync.onSynced = controller.load;
      offline.sync.start();
    }
    return controller;
  }

  @override
  void dispose() {
    _ownedGoogleBooks?.dispose();
    _offline?.sync.dispose();
    if (widget.libraryController == null) _library.dispose();
    if (widget.memoryController == null) _memory.dispose();
    if (widget.goalController == null) _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppFontTheme>(
      valueListenable: AppFontThemeController.current,
      builder: (context, fontTheme, _) => ValueListenableBuilder<AppColorTheme>(
        valueListenable: AppColorThemeController.current,
        builder: (context, colorTheme, _) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.mode,
            builder: (context, themeMode, _) {
              // The status bar sits over the app's own background, so its
              // icons have to contrast with *that* — with the app forced
              // to light while the phone is in dark mode, the system's
              // own choice would render them invisible.
              final isDark =
                  themeMode == ThemeMode.dark ||
                  (themeMode == ThemeMode.system &&
                      MediaQuery.platformBrightnessOf(context) ==
                          Brightness.dark);

              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: isDark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark,
                child: SessionScope(
                  session: _session,
                  child: LibraryScope(
                    controller: _library,
                    child: MemoryScope(
                      controller: _memory,
                      child: GoalScope(
                        controller: _goal,
                        child: MaterialApp(
                          title: 'cactus',
                          debugShowCheckedModeBanner: false,
                          theme: AppTheme.lightWith(colorTheme, fontTheme),
                          darkTheme: AppTheme.darkWith(colorTheme, fontTheme),
                          themeMode: themeMode,
                          scrollBehavior: AppScrollBehavior(),
                          // Screen views come from each route's own name
                          // rather than a line in every page's initState —
                          // see [AppAnalytics].
                          navigatorObservers: AppAnalytics.navigatorObservers,
                          // The intro is a tour, not a gate: `_bootstrap`
                          // has already opened the session, and
                          // [WelcomePage] asks for nothing. It shows once
                          // per install and replaces the whole stack with
                          // [RootShell] on the way out.
                          home: widget.showOnboarding
                              ? const WelcomePage()
                              : const RootShell(),
                          // The offline indicator in every page header reads
                          // the queue through this; without an offline layer
                          // (tests) it reads connectivity alone.
                          builder: (context, child) {
                            final offline = _offline;
                            if (offline == null || child == null) {
                              return child ?? const SizedBox.shrink();
                            }
                            return SyncScope(
                              queue: offline.queue,
                              coordinator: offline.sync,
                              child: child,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
