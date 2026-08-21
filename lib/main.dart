import 'dart:async';

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/diagnostics/app_logger.dart';
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

  // `.env` is a development convenience, not a requirement — a release
  // build configured through --dart-define has no such file and must
  // still start. See [Env].
  try {
    await dotenv.load(fileName: '.env');
  } on Object catch (error) {
    AppLogger.info(
      'main',
      'No .env file loaded ($error); using --dart-define.',
    );
  }

  final missing = Env.missingKeys;
  if (missing.isNotEmpty) {
    // A misconfigured build fails here, once, with the list of what is
    // missing — rather than at whichever screen first happens to touch
    // one of these and throwing an opaque StateError at the reader.
    AppLogger.error('main', 'Missing configuration: ${missing.join(', ')}.');
    runApp(StartupFailureApp(missingKeys: missing));
    return;
  }

  if (Env.isLeakingConfigInRelease) {
    AppLogger.warning(
      'main',
      'Release build is reading configuration from the bundled .env asset. '
          'Build with --dart-define instead so nothing is readable inside '
          'the shipped bundle.',
    );
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
    reportingFailure(
      const PurchasesService().identify(userId),
      source: 'main',
      message: 'Could not restore the RevenueCat identity at startup.',
    );
  }

  runApp(const BookApp());
}

class BookApp extends StatefulWidget {
  const BookApp({
    super.key,
    this.libraryController,
    this.sessionService,
    this.profileRepository,
    this.alwaysShowOnboarding = false,
  });

  /// Injection point for tests: pass a controller backed by fakes to
  /// drive the library without Supabase or Google Books. In the app this
  /// is null and the real graph below is composed instead.
  final LibraryController? libraryController;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) {
        return LibraryScope(
          controller: _library,
          child: MaterialApp(
            title: 'cactus',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            scrollBehavior: AppScrollBehavior(),
            home: (_signedIn && !widget.alwaysShowOnboarding)
                ? const RootShell()
                : WelcomePage(session: _session, profiles: _profiles),
          ),
        );
      },
    );
  }
}
