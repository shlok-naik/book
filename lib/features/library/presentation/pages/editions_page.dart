import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/book_edition.dart';
import '../../domain/library_book.dart';
import '../controllers/book_detail_controller.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import '../widgets/book_cover.dart';

/// Opens the editions gallery for the book whose detail page owns
/// [detail]. Pushed the same way `openBookDetail` pushes its page — a named
/// `MaterialPageRoute`, so the screen shows up in analytics.
///
/// [detail] is the detail page's own controller, handed over rather than
/// rebuilt: the editions it already loaded (or is loading) appear here
/// instantly, a retry here fills the detail page's editions summary too,
/// and nothing is fetched twice. The detail page is underneath this route
/// for as long as it's open, so the controller outlives it.
Future<void> openBookEditions(
  BuildContext context, {
  required String userBookId,
  required BookDetailController detail,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'book_editions'),
      builder: (_) => EditionsPage(userBookId: userBookId, detail: detail),
    ),
  );
}

/// Every ebook and physical edition of one book, as a small library of
/// covers — each cover with its publisher underneath — where tapping one
/// marks it as the edition the reader owns (and tapping it again clears
/// that). Owning an edition makes it the book everywhere for this reader:
/// its cover on the shelf, its publisher and ISBN on the book page, its
/// length for progress — see `LibraryBook.displayBook`.
///
/// The owned edition is shelf state, so the tap goes through
/// `LibraryController.setOwnedEdition` like every other shelf change; the
/// list itself comes from [BookDetailController.editions]. Loading, a
/// failed fetch (with retry), an empty result and a book removed from the
/// shelf while this page was open each have their own state.
class EditionsPage extends StatefulWidget {
  const EditionsPage({
    super.key,
    required this.userBookId,
    required this.detail,
  });

  final String userBookId;
  final BookDetailController detail;

  @override
  State<EditionsPage> createState() => _EditionsPageState();
}

class _EditionsPageState extends State<EditionsPage> {
  static const _messageLifetime = Duration(seconds: 3);

  /// Covers never grow past this, however wide the window.
  static const _maxTileWidth = 132.0;

  /// Room under a cover for the publisher (two lines) and format/year.
  static const _captionExtent = 64.0;

  /// The edition whose "owned" change is being saved, if any. Taps are
  /// ignored until it lands so two quick taps can't race.
  String? _saving;

  String? _message;
  ConfirmationTone _messageTone = ConfirmationTone.neutral;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    // Opened after the first load failed (or before it ever ran): start
    // another. After the first frame, not here — `loadEditions` notifies
    // synchronously, and the detail page underneath listens to the same
    // controller, so notifying mid-build would mark it dirty during a
    // build it isn't part of.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editions = widget.detail.editions;
      if (mounted && !editions.hasData && !editions.isLoading) {
        unawaited(widget.detail.loadEditions());
      }
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  void _showMessage(
    String message, [
    ConfirmationTone tone = ConfirmationTone.neutral,
  ]) {
    setState(() {
      _message = message;
      _messageTone = tone;
    });
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _toggle(LibraryBook entry, BookEdition edition) async {
    final id = edition.id;
    if (id == null || _saving != null) return;
    final owned = entry.progress.ownedEditionId == id;
    AppHaptics.selection();
    setState(() => _saving = id);

    LibraryActionResult result;
    try {
      result = await LibraryScope.read(
        context,
      ).setOwnedEdition(entry.id, owned ? null : edition);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'EditionsPage',
        'Saving the owned edition failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure("Couldn't save edition.");
    }
    if (!mounted) return;
    setState(() => _saving = null);

    if (result.success) {
      AppHaptics.accepted();
      // The controller's message says when the page was rescaled to the
      // new copy's length ("now page 498 of 639"), so show it verbatim.
      _showMessage(
        result.message ??
            (owned ? 'Cleared your edition' : 'Saved your edition'),
        ConfirmationTone.success,
      );
    } else {
      AppHaptics.rejected();
      _showMessage(
        result.message ?? "Couldn't save which edition you own.",
        ConfirmationTone.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = LibraryScope.of(context).findById(widget.userBookId);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsHeader(title: 'editions'),
              Expanded(
                child: entry == null
                    ? const _CenteredNote('no longer on your shelf.')
                    : ListenableBuilder(
                        listenable: widget.detail,
                        builder: (context, _) => _body(entry),
                      ),
              ),
              if (_message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: ConfirmationPill(
                      message: message,
                      tone: _messageTone,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(LibraryBook entry) {
    final colors = context.colors;
    final section = widget.detail.editions;
    final editions = section.data ?? const <BookEdition>[];

    if (section.isLoading && !section.hasData) {
      return const _CenteredNote(
        'finding ebook and physical editions…',
        showProgress: true,
      );
    }
    if (section.error != null && !section.hasData) {
      return _CenteredNote(
        section.error!,
        actionLabel: 'try again',
        onAction: widget.detail.loadEditions,
      );
    }
    if (editions.isEmpty) {
      return const _CenteredNote(
        'google books has no ebook or physical editions listed for this '
        'book.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / _maxTileWidth).ceil().clamp(2, 6);
        final tileWidth = (width - AppSpacing.md * (columns - 1)) / columns;
        final tileHeight = tileWidth / BookCover.aspectRatio + _captionExtent;

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.lg,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: entry.book.title,
                        style: context.fonts.bookTitle(
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' · ${editions.length} '
                            '${editions.length == 1 ? 'edition' : 'editions'}'
                            ' — tap the one you own.',
                      ),
                    ],
                  ),
                  style: context.fonts.body(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpacing.lg,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: tileWidth / tileHeight,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final edition = editions[index];
                final id = edition.id;
                return _EditionCover(
                  key: ValueKey(edition.googleBooksId),
                  edition: edition,
                  bookTitle: entry.book.title,
                  owned: id != null && id == entry.progress.ownedEditionId,
                  saving: id != null && id == _saving,
                  onTap: id == null || (_saving != null && _saving != id)
                      ? null
                      : () => _toggle(entry, edition),
                );
              }, childCount: editions.length),
            ),
            // A failed refresh keeps the covers already shown and says so.
            if (section.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: _CenteredNote(
                    section.error!,
                    actionLabel: 'try again',
                    onAction: widget.detail.loadEditions,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        );
      },
    );
  }
}

/// One edition in the gallery: its cover (the title placeholder when
/// Google has none, or it fails to load), the publisher, and format · year.
/// The owned edition wears an accent outline and a check.
class _EditionCover extends StatefulWidget {
  const _EditionCover({
    super.key,
    required this.edition,
    required this.bookTitle,
    required this.owned,
    required this.saving,
    required this.onTap,
  });

  final BookEdition edition;
  final String bookTitle;
  final bool owned;
  final bool saving;

  /// Null for an edition that can't be owned (not cached yet), or while a
  /// different edition's change is being saved.
  final VoidCallback? onTap;

  @override
  State<_EditionCover> createState() => _EditionCoverState();
}

class _EditionCoverState extends State<_EditionCover> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final edition = widget.edition;
    final format = edition.format == EditionFormat.ebook ? 'ebook' : 'physical';
    final publisher = edition.publisher ?? 'unknown publisher';
    final details = [format, ?edition.year].join(' · ');
    final highlighted = widget.owned || _focused || _hovered;

    return Semantics(
      button: widget.onTap != null,
      selected: widget.owned,
      label:
          '${format == 'ebook' ? 'Ebook' : 'Physical'} edition'
          '${edition.year == null ? '' : ' from ${edition.year}'}, '
          'published by $publisher.'
          '${widget.owned ? ' You own this edition.' : ''}',
      hint: widget.edition.id == null
          ? null
          : widget.owned
          ? 'Double tap to clear it as the edition you own.'
          : 'Double tap to mark it as the edition you own.',
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.onTap != null,
        mouseCursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap?.call(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                      border: Border.all(
                        width: 2,
                        color: highlighted
                            ? colors.accent.withValues(
                                alpha: widget.owned ? 1 : 0.5,
                              )
                            : Colors.transparent,
                      ),
                    ),
                    child: BookCover(
                      title: edition.title,
                      author: edition.author,
                      coverUrl: edition.coverUrl,
                      isbn: edition.isbn13 ?? edition.isbn10,
                    ),
                  ),
                  if (widget.owned || widget.saving)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: widget.saving
                            ? CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.background,
                              )
                            : Icon(
                                Icons.check,
                                size: 16,
                                color: colors.background,
                              ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                publisher,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.fonts.body(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.fonts.interface(
                  fontSize: 11,
                  color: widget.owned ? colors.accent : colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading, error and empty states — one centered line, an optional
/// spinner, and an optional action — announced as they appear.
class _CenteredNote extends StatelessWidget {
  const _CenteredNote(
    this.text, {
    this.actionLabel,
    this.onAction,
    this.showProgress = false,
  });

  final String text;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = actionLabel;
    final action = onAction;

    return Center(
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.fonts.interface(
                fontSize: 13,
                height: 1.6,
                color: colors.secondaryText,
              ),
            ),
            if (label != null && action != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: action,
                child: Text(
                  label,
                  style: context.fonts.interface(
                    fontSize: 13,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
