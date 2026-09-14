import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../domain/collections.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import 'detail_text_field.dart';

/// The three kinds of collection the panel can make, in tab order.
enum CollectionKind { shelves, tags, series }

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
    final labelStyle = GoogleFonts.jetBrainsMono(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: DefaultTabController(
          length: CollectionKind.values.length,
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
                    'make',
                    style: GoogleFonts.jetBrainsMono(
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
                  ],
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _MakeTab(kind: CollectionKind.shelves),
                      _MakeTab(kind: CollectionKind.tags),
                      _MakeTab(kind: CollectionKind.series),
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
    setState(() {
      _busy = true;
      _message = null;
    });

    LibraryActionResult result;
    try {
      result = await switch (widget.kind) {
        CollectionKind.shelves => library.makeShelf(name),
        CollectionKind.tags => library.makeTag(name),
        CollectionKind.series => library.makeSeries(name),
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

  /// Ids mid-delete, so a second tap while one is still saving is ignored
  /// rather than sent twice.
  final _deleting = <String>{};

  Future<void> _delete(LibraryController library, String id) async {
    if (_deleting.contains(id)) return;
    setState(() => _deleting.add(id));
    AppHaptics.selection();
    try {
      final result = await switch (widget.kind) {
        CollectionKind.shelves => library.deleteShelf(id),
        CollectionKind.tags => library.deleteTag(id),
        CollectionKind.series => library.deleteSeries(id),
      };
      if (!result.success) AppHaptics.rejected();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'CollectionsSheet',
        'Removing a ${_copy.singular} failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final copy = _copy;
    final entries = switch (widget.kind) {
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

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.lg),
      children: [
        DetailTextField(
          key: ValueKey('make-${copy.singular}-field'),
          controller: _name,
          hintText: copy.hint,
          maxLength: copy.maxLength,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          semanticsLabel: 'New ${copy.singular} name',
          onSubmitted: (_) => _make(),
        ),
        const SizedBox(height: AppSpacing.md),
        SoftPillButton(
          key: ValueKey('make-${copy.singular}-button'),
          label: _busy ? 'making…' : 'make ${copy.singular}',
          onPressed: _busy ? null : _make,
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              key: ValueKey('make-${copy.singular}-message'),
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: _succeeded ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ],
        if (entries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            label: 'Your ${widget.kind.name}, ${entries.length}',
            excludeSemantics: true,
            child: Text(
              'yours',
              style: GoogleFonts.jetBrainsMono(
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
              for (final entry in entries)
                _NameChip(
                  name: entry.name,
                  busy: _deleting.contains(entry.id),
                  onRemove: () => _delete(library, entry.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.name,
    required this.busy,
    required this.onRemove,
  });

  final String name;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Container(
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
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: colors.primaryText,
              ),
            ),
            Semantics(
              // Its own node, so "Remove sci-fi" isn't merged into the
              // chip's text and read as one unactionable label.
              container: true,
              button: true,
              label: 'Remove $name',
              excludeSemantics: true,
              child: InkResponse(
                onTap: busy ? null : onRemove,
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
