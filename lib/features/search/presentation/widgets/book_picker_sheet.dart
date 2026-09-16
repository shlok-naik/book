import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/network/connectivity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/domain/library_search.dart';
import '../../../library/presentation/library_scope.dart';
import '../controllers/book_search_controller.dart';
import 'book_rows.dart';

/// What the reader picked in [showBookPicker].
sealed class BookPick {
  const BookPick();
}

/// A book already on the shelf.
final class ShelfPick extends BookPick {
  const ShelfPick(this.entry);

  final LibraryBook entry;
}

/// A Google Books volume, not necessarily on the shelf.
final class CataloguePick extends BookPick {
  const CataloguePick(this.volume);

  final GoogleBook volume;
}

/// Asks the reader which book they meant — what the smart parser shows
/// when a command names no book, or names one too loosely to be sure
/// ("finish harry potter"). Two tabs: **your library**, filtered by what's
/// typed, and **google books**, searched as they type. [query] starts both
/// off with the words the reader already used; [prompt] says why it's
/// asking. Resolves to the pick, or null when dismissed.
Future<BookPick?> showBookPicker(
  BuildContext context, {
  String query = '',
  String prompt = 'which book?',
}) {
  return showModalBottomSheet<BookPick>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'book_picker'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => BookPickerSheet(query: query, prompt: prompt),
  );
}

class BookPickerSheet extends StatefulWidget {
  const BookPickerSheet({super.key, this.query = '', required this.prompt});

  final String query;
  final String prompt;

  @override
  State<BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<BookPickerSheet>
    with SingleTickerProviderStateMixin {
  static const _debounce = Duration(milliseconds: 350);

  late final TextEditingController _text = TextEditingController(
    text: widget.query,
  );
  late final TabController _tabs = TabController(length: 2, vsync: this);
  BookSearchController? _search;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_search != null) return;
    _search = BookSearchController(lookup: LibraryScope.read(context).lookup);
    if (widget.query.trim().isNotEmpty &&
        !ConnectivityController.isOffline.value) {
      unawaited(_search!.search(widget.query));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search?.dispose();
    _tabs.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) unawaited(_search!.search(value));
    });
  }

  void _pick(BookPick pick) {
    AppHaptics.selection();
    Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final library = LibraryScope.of(context);
    final query = _text.text.trim();
    final shelf = [
      for (final entry in library.books)
        if (query.isEmpty || LibrarySearch.matches(entry, query)) entry,
    ];
    final style = context.fonts.interface(
      fontSize: 15,
      color: colors.primaryText,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: colors.divider),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.prompt,
                  style: context.fonts.interface(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('book-picker-field'),
                // Enter submits without closing the keyboard (a TextField's default
                // is to unfocus on the action button).
                onEditingComplete: () {},
                controller: _text,
                onChanged: _onChanged,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                style: style,
                cursorColor: colors.accent,
                decoration: InputDecoration(
                  hintText: 'title or author',
                  hintStyle: style.copyWith(color: colors.secondaryText),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: colors.background,
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
              TabBar(
                controller: _tabs,
                labelColor: colors.accent,
                unselectedLabelColor: colors.secondaryText,
                indicatorColor: colors.accent,
                labelStyle: context.fonts.interface(fontSize: 14),
                tabs: const [
                  Tab(
                    key: ValueKey('book-picker-library'),
                    text: 'your library',
                  ),
                  Tab(
                    key: ValueKey('book-picker-google'),
                    text: 'google books',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    shelf.isEmpty
                        ? _Note(
                            query.isEmpty
                                ? 'your library is empty.'
                                : 'no books on your shelf match "$query".',
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            children: [
                              for (final entry in shelf)
                                BookRow.shelf(
                                  key: ValueKey('picker-shelf-${entry.id}'),
                                  entry: entry,
                                  shelfName: library.shelfName(
                                    library.placementOf(entry),
                                  ),
                                  onTap: () => _pick(ShelfPick(entry)),
                                ),
                            ],
                          ),
                    ListenableBuilder(
                      listenable: _search!,
                      builder: (context, _) => _catalogue(query),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catalogue(String query) {
    final search = _search!;
    if (ConnectivityController.isOffline.value) {
      return const _Note('searching google books needs a connection.');
    }
    if (query.isEmpty) return const _Note('type a title to search.');
    if (search.isSearching && search.results.isEmpty) {
      return const _Note('searching…');
    }
    if (search.errorMessage case final error?) return _Note(error);
    if (search.results.isEmpty) {
      return _Note('google books has nothing for "$query".');
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final volume in search.results)
          BookRow.volume(
            key: ValueKey('picker-volume-${volume.id}'),
            volume: volume,
            onTap: () => _pick(CataloguePick(volume)),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.fonts.interface(
          fontSize: 13,
          color: context.colors.secondaryText,
        ),
      ),
    );
  }
}
