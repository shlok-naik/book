import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/supabase/supabase_service.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/library/data/book_cache_repository.dart';
import 'features/library/data/google_books_api_client.dart';
import 'features/library/data/user_book_repository.dart';
import 'features/library/domain/book_lookup_service.dart';
import 'features/library/presentation/controllers/library_controller.dart';
import 'features/library/presentation/library_scope.dart';
import 'features/shell/presentation/pages/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await SupabaseService.init();
  runApp(const BookApp());
}

class BookApp extends StatefulWidget {
  const BookApp({super.key, this.libraryController});

  /// Injection point for tests: pass a controller backed by fakes to
  /// drive the library without Supabase or Google Books. In the app this
  /// is null and the real graph below is composed instead.
  final LibraryController? libraryController;

  @override
  State<BookApp> createState() => _BookAppState();
}

class _BookAppState extends State<BookApp> {
  /// The app's only composition root for the library feature: clients
  /// and repositories are built here once and injected downward, so no
  /// widget constructs its own (see CLAUDE.md § Dependency Injection).
  late final LibraryController _library =
      widget.libraryController ?? _buildLibraryController();

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
            title: 'Book',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            scrollBehavior: AppScrollBehavior(),
            home: const RootShell(),
          ),
        );
      },
    );
  }
}
