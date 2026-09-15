import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../domain/collections.dart';
import '../../domain/library_book.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import 'book_cover.dart';
import 'detail_text_field.dart';
import 'removal_confirmations.dart';

// The collection kinds live in the domain now — `remove shelf|tag|series`
// resolves against them too — and are re-exported for callers of the sheet.
export '../../domain/collections.dart' show CollectionKind;

/// Opens the library's "+" panel — shelves, tags and series tabs, each
/// making one of its kind. Reached from the "+" beside the library's search
/// icon.
///
/// It makes things through exactly the functions the typed commands use —
/// [LibraryController.makeShelf] (`make shelf`), [LibraryController.makeTag]
/// (`make tag`) and [LibraryController.makeSeries] (`make series`) — so a
/// name is validated, de-duplicated and stored one way whichever surface it
/// came from. It never applies anything to a book: that is `move`,
/// `add tag` and `add series`.
Future<void> showCollectionsSheet(
  BuildContext context, {
  CollectionKind initialTab = CollectionKind.shelves,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    // Named so it shows up in the analytics funnel.
    routeSettings: const RouteSettings(name: 'make_collections'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => CollectionsSheet(initialTab: initialTab),
  );
}

class CollectionsSheet extends StatelessWidget {
  const CollectionsSheet({super.key, this.initialTab = CollectionKind.shelves});

  final CollectionKind initialTab;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    // Tall enough for a field, a button and a few rows of names; the
    // keyboard's inset is added below so the field is never covered.
    final height = (media.size.height * 0.6).clamp(360.0, 560.0);
    final labelStyle = context.fonts.interface(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: CollectionKind.values.length + 1,
          initialIndex: initialTab.index,
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
                    'make & remove',
                    style: context.fonts.interface(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TabBar(
                  labelColor: colors.accent,
                  unselectedLabelColor: colors.secondaryText,
                  indicatorColor: colors.accent,
                  dividerColor: colors.divider,
                  labelStyle: labelStyle,
                  unselectedLabelStyle: labelStyle.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  onTap: (_) => AppHaptics.selection(),
                  tabs: const [
                    Tab(
                      key: ValueKey('collections-tab-shelves'),
                      text: 'shelves',
                    ),
                    Tab(key: ValueKey('collections-tab-tags'), text: 'tags'),
                    Tab(
                      key: ValueKey('collections-tab-series'),
                      text: 'series',
                    ),
                    Tab(key: ValueKey('collections-tab-books'), text: 'books'),
                  ],
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _MakeTab(kind: CollectionKind.shelves),
                      _MakeTab(kind: CollectionKind.tags),
                      _MakeTab(kind: CollectionKind.series),
                      _BooksTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: a name field, a "make" button, the outcome of the last attempt,
/// and every collection of this kind the reader already has.
class _MakeTab extends StatefulWidget {
  const _MakeTab({required this.kind});

  final CollectionKind kind;

  @override
  State<_MakeTab> createState() => _MakeTabState();
}

class _MakeTabState extends State<_MakeTab> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();

  /// True while a make is in flight, so a double tap can't send two.
  bool _busy = false;

  /// The last attempt's outcome — shown under the field, and announced.
  String? _message;
  bool _succeeded = false;

  // Keeps a half-typed name when the reader flips to another tab and back.
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ({String singular, String hint, int maxLength}) get _copy =>
      switch (widget.kind) {
        CollectionKind.shelves => (
          singular: 'shelf',
          hint: 'shelf name, like summer reads',
          maxLength: CollectionNames.shelfMaxLength,
        ),
        CollectionKind.tags => (
          singular: 'tag',
          hint: 'tag, like sci-fi',
          maxLength: CollectionNames.tagMaxLength,
        ),
        CollectionKind.series => (
          singular: 'series',
          hint: 'series name, like the expanse',
          maxLength: CollectionNames.seriesMaxLength,
        ),
      };

  Future<void> _make() async {
    if (_busy) return;
    final name = _name.text;
    final library = LibraryScope.read(context);
    // Read at submit time rather than cached, same reasoning `HomePage`
    // gives for `remember`/`recommend`: a plan bought mid-sheet takes
    // effect on the very next tap.
    final isPro = PlanController.isPro.value;
    final canMake = switch (widget.kind) {
      CollectionKind.shelves => library.canMakeShelf(isPro),
      CollectionKind.tags => library.canMakeTag(isPro),
      CollectionKind.series => library.canMakeSeries(isPro),
    };
    if (!canMake) {
      await showPaywallPopup(context, feature: PaywallFeature.readingUnlocked);
      if (mounted) setState(() {}); // re-reads PlanController.isPro below
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    LibraryActionResult result;
    try {
      result = await switch (widget.kind) {
        CollectionKind.shelves => library.makeShelf(name, isPro: isPro),
        CollectionKind.tags => library.makeTag(name, isPro: isPro),
        CollectionKind.series => library.makeSeries(name, isPro: isPro),
      };
    } on Object catch (error, stackTrace) {
      // The make functions report failures as results; this is for
      // anything they didn't anticipate.
      AppLogger.error(
        'CollectionsSheet',
        'Making a ${_copy.singular} failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = LibraryActionResult.failure(
        "We couldn't make that ${_copy.singular}. Try again.",
      );
    }
    if (!mounted) return;

    if (result.success) {
      AppHaptics.accepted();
      _name.clear();
    } else {
      AppHaptics.rejected();
    }
    setState(() {
      _busy = false;
      _succeeded = result.success;
      _message = result.message;
    });
  }

  /// Unmakes the collection called [name] — the same resolution, confirmation
  /// and removal `remove shelf|tag|series <name>` uses on the add tab.
  Future<void> _remove(String name) async {
    if (_busy) return;
    final library = LibraryScope.read(context);
    final resolved = library.resolveRemoval(widget.kind, name: name);
    final removal = resolved.removal;
    if (removal is! UnmakeCollection) {
      AppHaptics.rejected();
      setState(() {
        _succeeded = false;
        _message = resolved.failure;
      });
      return;
    }
    final confirmed = await confirmUnmake(context, removal);
    if (!mounted || !confirmed) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    LibraryActionResult result;
    try {
      result = await library.applyRemoval(removal);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'CollectionsSheet',
        'Removing a ${_copy.singular} failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = LibraryActionResult.failure(
        "We couldn't remove that ${_copy.singular}. Try again.",
      );
    }
    if (!mounted) return;
    if (result.success) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
    setState(() {
      _busy = false;
      _succeeded = result.success;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final copy = _copy;
    final names = switch (widget.kind) {
      CollectionKind.shelves => [
        for (final s in library.shelves) (id: s.id, name: s.name),
      ],
      CollectionKind.tags => [
        for (final t in library.tags) (id: t.id, name: t.name),
      ],
      CollectionKind.series => [
        for (final s in library.mySeries) (id: s.id, name: s.name),
      ],
    };
    final message = _message;
    // Faded whenever this tab can't make another one on the reader's plan
    // — the same "faded, never hidden" treatment settings' customisation
    // row uses, so the limit reads before a reader types anything rather
    // than as a paywall after they submit. Asks the exact rule [_make]
    // enforces: the free plan has no custom shelves at all, and caps tags
    // at 2 and series at 1, so those two tabs fade once the cap is
    // reached (and un-fade if one is removed or pro is bought). Still
    // tappable: submitting while faded is how the paywall opens.
    final isPro = PlanController.isPro.value;
    final locked = !switch (widget.kind) {
      CollectionKind.shelves => library.canMakeShelf(isPro),
      CollectionKind.tags => library.canMakeTag(isPro),
      CollectionKind.series => library.canMakeSeries(isPro),
    };

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.lg),
      children: [
        Opacity(
          key: ValueKey('make-${copy.singular}-fade'),
          opacity: locked ? 0.4 : 1,
          child: Column(
            children: [
              GestureDetector(
                onTap: locked ? _make : null,
                child: AbsorbPointer(
                  absorbing: locked,
                  child: DetailTextField(
                    key: ValueKey('make-${copy.singular}-field'),
                    controller: _name,
                    hintText: copy.hint,
                    maxLength: copy.maxLength,
                    enabled: !_busy && !locked,
                    textInputAction: TextInputAction.done,
                    semanticsLabel: 'New ${copy.singular} name',
                    onSubmitted: (_) => _make(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SoftPillButton(
                key: ValueKey('make-${copy.singular}-button'),
                label: _busy ? 'making…' : 'make ${copy.singular}',
                onPressed: _busy ? null : _make,
              ),
            ],
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: ValueKey('make-${copy.singular}-message'),
              style: context.fonts.body(
                fontSize: 13,
                height: 1.5,
                color: _succeeded ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ],
        if (names.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            label: 'Your ${widget.kind.name}, ${names.length}',
            excludeSemantics: true,
            child: Text(
              'yours',
              style: context.fonts.interface(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final item in names)
                _NameChip(
                  key: ValueKey('remove-${copy.singular}-${item.id}'),
                  name: item.name,
                  noun: copy.singular,
                  onRemove: _busy ? null : () => _remove(item.name),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One made collection, with an X that removes it (after confirming).
class _NameChip extends StatelessWidget {
  const _NameChip({
    super.key,
    required this.name,
    required this.noun,
    required this.onRemove,
  });

  final String name;

  /// "shelf", "tag" or "series" — for the remove button's label.
  final String noun;

  /// Null while another action in the tab is saving.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.primaryText,
            ),
          ),
          Semantics(
            button: true,
            label: 'Remove $noun $name',
            excludeSemantics: true,
            child: InkResponse(
              onTap: onRemove,
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(Icons.close, size: 14, color: colors.secondaryText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "+" panel's books tab: every book on the shelf, each with an X that
/// removes it from the library — the same confirmation and removal
/// `delete <book>` uses on the add tab, but by id, so a similar title can
/// never be the one removed. Finding a book here is the library page's own
/// search icon's job, not this tab's — it isn't duplicated.
class _BooksTab extends StatefulWidget {
  const _BooksTab();

  @override
  State<_BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<_BooksTab>
    with AutomaticKeepAliveClientMixin {
  /// The id being removed, so its row (and a second tap) is disabled.
  String? _removing;
  String? _message;
  bool _succeeded = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _remove(LibraryBook entry) async {
    if (_removing != null) return;
    final library = LibraryScope.read(context);
    final confirmed = await confirmRemoveBook(context, entry);
    if (!mounted || !confirmed) return;

    setState(() {
      _removing = entry.id;
      _message = null;
    });
    LibraryActionResult result;
    try {
      result = await library.deleteBookById(entry.id);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'CollectionsSheet',
        'Removing a book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure(
        "We couldn't remove that book. Try again.",
      );
    }
    if (!mounted) return;
    if (result.success) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
    setState(() {
      _removing = null;
      _succeeded = result.success;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final books = [...library.books]
      ..sort(
        (a, b) =>
            a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()),
      );
    final message = _message;

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.lg),
      children: [
        if (message != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: const ValueKey('remove-books-message'),
              style: context.fonts.body(
                fontSize: 13,
                height: 1.5,
                color: _succeeded ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (books.isEmpty)
          Text(
            'no books on your shelf.',
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          )
        else
          for (final entry in books)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 48,
                    child: BookCover(
                      title: entry.displayBook.title,
                      author: entry.displayBook.author,
                      coverUrl: entry.displayBook.coverUrl,
                      isbn:
                          entry.displayBook.isbn13 ?? entry.displayBook.isbn10,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.fonts.interface(
                            fontSize: 14,
                            color: colors.primaryText,
                          ),
                        ),
                        Text(
                          entry.book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.fonts.body(
                            fontSize: 12,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Remove ${entry.book.title} from your library',
                    excludeSemantics: true,
                    child: IconButton(
                      key: ValueKey('remove-book-${entry.id}'),
                      onPressed: _removing == null
                          ? () => _remove(entry)
                          : null,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
