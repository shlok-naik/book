import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/numbers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/book.dart';
import '../../domain/book_edition.dart';
import '../../domain/book_note.dart';
import '../../domain/library_book.dart';
import '../../domain/user_book.dart';
import '../controllers/book_detail_controller.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import '../widgets/book_cover.dart';
import '../widgets/detail_text_field.dart';
import '../widgets/info_section.dart';
import '../widgets/removal_confirmations.dart';
import '../widgets/series_selection_sheet.dart';
import '../widgets/shelf_selection_sheet.dart';
import '../widgets/star_rating_input.dart';
import '../widgets/tag_selection_sheet.dart';
import 'editions_page.dart';

/// Opens the detail page for [entry]. The one way it should be pushed, so
/// the route always carries its analytics name — see `AppAnalytics`.
Future<void> openBookDetail(BuildContext context, LibraryBook entry) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'book_detail'),
      builder: (_) => BookDetailPage(userBookId: entry.id),
    ),
  );
}

/// Everything about one book on the reader's shelf, top to bottom in the
/// order a reader looks for it:
///
/// 1. **The book** — cover, title, author, and one line saying where the
///    reader is with it ("reading · 78%") and which edition they own;
/// 2. **Key facts** — pages, published, publisher, language — in a strip
///    that reads at a glance;
/// 3. **Editions** — one row that opens the [EditionsPage] gallery;
/// 4. **Your reading** — progress (page and percent, kept in sync) and
///    rating (finished books only);
/// 5. **Tags** and **comments**;
/// 6. **About** — the blurb, genre, ISBN and the Google Books rating.
///
/// Every action has a button here, so a reader never needs a command:
/// **shelf** opens [showShelfSelectionSheet] (the same move a drag or
/// `move <book> <shelf>` makes), **read again** restarts a finished book,
/// and **remove from library** at the bottom deletes it after the same
/// confirmation `delete <book>` asks.
///
/// ## Where the state lives
///
/// * The **shelf row** — status, page, rating, owned edition — is read
///   from [LibraryController] by id on every build, and every change to it
///   goes through that controller, the single mutation point for shelf
///   state.
/// * Everything else — extended info, editions, tags, comments — is
///   per-page state in a [BookDetailController], built once when the page
///   opens and thrown away when it closes. The editions page borrows the
///   same controller rather than fetching again.
///
/// Every section loads and fails independently, with its own retry, so
/// Google Books being unreachable never hides the reader's own notes.
class BookDetailPage extends StatefulWidget {
  const BookDetailPage({super.key, required this.userBookId});

  final String userBookId;

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  static const _messageLifetime = Duration(seconds: 3);

  BookDetailController? _detail;

  final _page = TextEditingController();
  final _percent = TextEditingController();
  final _pageFocus = FocusNode();
  final _percentFocus = FocusNode();
  final _comment = TextEditingController();

  /// The page the progress fields were last filled from, so an outside
  /// change (a command logged elsewhere, a save landing) refills them —
  /// but typing in them doesn't get overwritten mid-edit.
  int? _filledFromPage;
  ReadingStatus? _filledFromStatus;
  String? _progressError;

  bool _savingProgress = false;

  /// Guards against a double tap pushing the editions page twice.
  bool _openingEditions = false;

  String? _message;
  ConfirmationTone _messageTone = ConfirmationTone.neutral;
  Timer? _messageTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_detail != null) return;
    final library = LibraryScope.read(context);
    final entry = library.findById(widget.userBookId);
    if (entry == null) return;
    _detail = BookDetailController(
      userBookId: entry.id,
      book: entry.book,
      details: library.details,
      notes: library.notes,
      findTag: library.findTag,
      onTagsChanged: library.notifyTagsChanged,
    );
    // Loads are async and notify as they land; nothing here depends on
    // them finishing. `load` never throws — each section records its own
    // failure.
    unawaited(_detail!.load());
  }

  @override
  void dispose() {
    _detail?.dispose();
    _page.dispose();
    _percent.dispose();
    _pageFocus.dispose();
    _percentFocus.dispose();
    _comment.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- feedback

  /// Reports a finished action: a haptic for its outcome and, when there is
  /// something to say, the same confirmation pill the add tab uses.
  void _report(LibraryActionResult result) {
    if (!mounted) return;
    if (result.success) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
    final message = result.message;
    if (message != null) {
      _showMessage(
        message,
        result.success ? ConfirmationTone.success : ConfirmationTone.failure,
      );
    }
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

  /// Runs a user action that returns a result, turning anything it throws
  /// that it shouldn't into a failure the reader sees, rather than an
  /// unhandled error and a control that silently did nothing.
  Future<void> _run(
    String what,
    Future<LibraryActionResult> Function() action,
  ) async {
    try {
      _report(await action());
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookDetailPage',
        'Unexpected failure: $what.',
        error: error,
        stackTrace: stackTrace,
      );
      _report(LibraryActionResult.failure("Couldn't $what."));
    }
  }

  // ----------------------------------------------------------------- actions

  bool _actionBusy = false;

  Future<void> _changeShelf(LibraryBook entry) async {
    if (_actionBusy) return;
    AppHaptics.selection();
    final library = LibraryScope.read(context);
    final picked = await showShelfSelectionSheet(
      context,
      current: library.placementOf(entry),
    );
    if (picked == null || !mounted) return;
    _actionBusy = true;
    try {
      await _run('move this book', () async {
        final result = await library.moveBook(entry.id, picked, 0);
        return result.success && result.message == null
            ? LibraryActionResult.success(
                'Moved to ${library.shelfName(picked)}',
              )
            : result;
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _readAgain(LibraryBook entry) async {
    if (_actionBusy) return;
    _actionBusy = true;
    try {
      await _run(
        'restart this book',
        () => LibraryScope.read(context).restartBookById(entry.id),
      );
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _remove(LibraryBook entry) async {
    if (_actionBusy) return;
    AppHaptics.selection();
    final confirmed = await confirmRemoveBook(context, entry);
    if (!confirmed || !mounted) return;
    _actionBusy = true;
    final library = LibraryScope.read(context);
    final navigator = Navigator.of(context);
    try {
      final result = await library.deleteBookById(entry.id);
      if (!mounted) return;
      if (result.success) {
        AppHaptics.accepted();
        unawaited(navigator.maybePop());
      } else {
        _report(result);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookDetailPage',
        'Removing the book failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      _report(const LibraryActionResult.failure("Couldn't remove book."));
    } finally {
      _actionBusy = false;
    }
  }

  // ---------------------------------------------------------------- editions

  Future<void> _openEditions(LibraryBook entry) async {
    final detail = _detail;
    if (detail == null || _openingEditions) return;
    _openingEditions = true;
    AppHaptics.selection();
    try {
      await openBookEditions(context, userBookId: entry.id, detail: detail);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookDetailPage',
        'Opening the editions page failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showMessage("Couldn't open editions.", ConfirmationTone.failure);
      }
    } finally {
      _openingEditions = false;
    }
  }

  // ---------------------------------------------------------------- progress

  /// Refills the page/percent fields from [entry] whenever its progress
  /// changed from outside and neither field is being edited.
  void _syncProgressFields(LibraryBook entry) {
    final editing = _pageFocus.hasFocus || _percentFocus.hasFocus;
    if (editing) return;
    if (_filledFromPage == entry.currentPage &&
        _filledFromStatus == entry.status) {
      return;
    }
    _filledFromPage = entry.currentPage;
    _filledFromStatus = entry.status;
    _page.text = '${entry.currentPage}';
    final completion = entry.completion;
    _percent.text = completion == null ? '' : _formatPercent(completion * 100);
    _progressError = null;
  }

  /// Page typed → percent follows. Invalid or out-of-range input leaves
  /// the percent alone and says why, rather than silently clamping.
  void _onPageChanged(LibraryBook entry, String text) {
    final page = int.tryParse(text.trim());
    final total = entry.pageCount;
    setState(() {
      if (text.trim().isEmpty) {
        _progressError = null;
        return;
      }
      if (page == null || page < 0) {
        _progressError = 'Enter a page number.';
      } else if (total != null && page > total) {
        _progressError = '"${entry.book.title}" only has $total pages.';
      } else {
        _progressError = null;
        if (total != null) _percent.text = _formatPercent(page / total * 100);
      }
    });
  }

  /// Percent typed → page follows, through the same conversion the
  /// `update <book> <percent>%` command uses.
  void _onPercentChanged(LibraryBook entry, String text) {
    final percent = double.tryParse(text.trim());
    setState(() {
      if (text.trim().isEmpty) {
        _progressError = null;
        return;
      }
      if (percent == null) {
        _progressError = 'Enter 0–100%.';
        return;
      }
      final resolved = LibraryController.pageForPercent(entry, percent);
      final page = resolved.page;
      if (page == null) {
        _progressError = resolved.failure;
      } else {
        _progressError = null;
        _page.text = '$page';
      }
    });
  }

  Future<void> _saveProgress(LibraryBook entry) async {
    if (_savingProgress) return;
    final page = int.tryParse(_page.text.trim());
    if (page == null) {
      setState(() => _progressError = 'Enter a page number.');
      AppHaptics.rejected();
      return;
    }
    if (_progressError != null) {
      AppHaptics.rejected();
      return;
    }
    if (page == entry.currentPage && entry.isReading) return;

    setState(() => _savingProgress = true);
    final library = LibraryScope.read(context);
    LibraryActionResult result;
    try {
      result = await library.updateProgressById(entry.id, page);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookDetailPage',
        'Saving progress failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      result = const LibraryActionResult.failure("Couldn't save progress.");
    }
    if (!mounted) return;
    setState(() {
      _savingProgress = false;
      // Force a refill from whatever the shelf now says — the saved page
      // on success, the old one after a rollback.
      _filledFromPage = null;
      if (!result.success) _progressError = result.message;
    });
    _report(result);
  }

  static String _formatPercent(double percent) => formatCompactNumber(percent);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final entry = library.findById(widget.userBookId);
    final detail = _detail;

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
              const SettingsHeader(title: 'book'),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: entry == null || detail == null
                    ? _Gone(colors: colors)
                    : ListenableBuilder(
                        listenable: detail,
                        builder: (context, _) => _content(entry, detail),
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

  Widget _content(LibraryBook entry, BookDetailController detail) {
    final library = LibraryScope.of(context);
    _syncProgressFields(entry);
    // The detailed row once it has loaded, else the shelf's own copy —
    // then as the reader's own edition, when they've picked one, so its
    // cover, publisher, ISBN and length are what the page shows.
    final work = detail.book.data ?? entry.book;
    final owned = entry.ownedEdition;
    final book = owned == null ? work : work.withEdition(owned);

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _Heading(entry: entry, book: book),
        const SizedBox(height: AppSpacing.lg),
        _FactsStrip(book: book, loading: detail.book.isLoading),
        const SizedBox(height: AppSpacing.md),
        InfoSection(
          rows: [
            _EditionsRow(
              section: detail.editions,
              owned: entry.ownedEdition,
              onTap: () => _openEditions(entry),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        InfoSection(
          title: 'your reading',
          rows: [
            _ValueRow(
              key: const ValueKey('book-shelf-row'),
              label: 'shelf',
              value: library.shelfName(library.placementOf(entry)),
              onTap: () => _changeShelf(entry),
            ),
            if (entry.isFinished)
              _ValueRow(
                key: const ValueKey('book-read-again-row'),
                label: 'read again',
                value: entry.rereadCount == 0
                    ? null
                    : 'read ${entry.rereadCount + 1} times',
                onTap: () => _readAgain(entry),
              ),
            _progressRow(entry),
            // A queued book hasn't been started — there's no date to show.
            if (entry.status != ReadingStatus.toBeRead) _datesRow(entry),
            _ratingRow(entry),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _seriesSection(entry, library),
        const SizedBox(height: AppSpacing.lg),
        _tagsSection(detail),
        const SizedBox(height: AppSpacing.lg),
        _commentsSection(entry, detail),
        const SizedBox(height: AppSpacing.lg),
        _aboutSection(book, detail, seriesLabel: library.seriesLabelFor(entry)),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: TextButton.icon(
            key: const ValueKey('book-remove'),
            onPressed: () => _remove(entry),
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: context.colors.primaryText,
            ),
            label: Text(
              'remove from library',
              style: context.fonts.interface(
                fontSize: 14,
                color: context.colors.primaryText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progressRow(LibraryBook entry) {
    final colors = context.colors;
    final total = entry.pageCount;
    final completion = entry.completion;
    final error = _progressError;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RowLabel(
            'progress',
            trailing: completion == null
                ? null
                : '${(completion * 100).round()}%',
          ),
          if (completion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'Progress',
              value: '${(completion * 100).round()} percent',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: completion,
                  minHeight: 4,
                  color: colors.accent,
                  backgroundColor: colors.divider,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: DetailTextField(
                  controller: _page,
                  hintText: 'page',
                  semanticsLabel: 'Current page',
                  suffixText: total == null ? null : '/ $total',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  onChanged: (text) => _onPageChanged(entry, text),
                  onSubmitted: (_) => _saveProgress(entry),
                ).withFocus(_pageFocus),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 96,
                child: DetailTextField(
                  controller: _percent,
                  hintText: total == null ? '—' : '0',
                  semanticsLabel: 'Percent complete',
                  suffixText: '%',
                  enabled: total != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  maxLength: 5,
                  onChanged: (text) => _onPercentChanged(entry, text),
                  onSubmitted: (_) => _saveProgress(entry),
                ).withFocus(_percentFocus),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: _savingProgress ? null : () => _saveProgress(entry),
                child: _savingProgress
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                          semanticsLabel: 'Saving progress',
                        ),
                      )
                    : Text(
                        'save',
                        style: context.fonts.interface(
                          fontSize: 13,
                          color: colors.accent,
                        ),
                      ),
              ),
            ],
          ),
          if (error != null || total == null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: error != null,
              child: Text(
                error ??
                    "google books doesn't list a page count, so progress is "
                        'by page only.',
                style: context.fonts.body(
                  fontSize: 12,
                  color: error == null
                      ? colors.secondaryText
                      : colors.primaryText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Start and finish dates. Filled in by `start`/`finish` (and moves onto
  /// the reading or finished shelf), and editable here: each is a button
  /// opening a date picker bounded to the past, and the controller refuses
  /// a finish before the start. The finish date only exists for a finished
  /// book.
  Widget _datesRow(LibraryBook entry) {
    final started = entry.progress.startedAt;
    final finished = entry.isFinished ? entry.progress.finishedAt : null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RowLabel('dates'),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  key: const ValueKey('book-started-date'),
                  label: 'started on',
                  date: started,
                  onTap: () => _pickDate(entry, finish: false),
                ),
              ),
              if (entry.isFinished) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DateField(
                    key: const ValueKey('book-finished-date'),
                    label: 'finished on',
                    date: finished,
                    onTap: () => _pickDate(entry, finish: true),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Opens a date picker for the start ([finish] false) or finish date,
  /// bounded so an impossible pair can't even be picked — no future dates,
  /// no start after the finish — then saves through
  /// [LibraryController.setDates], which checks the same rules.
  ///
  /// A finish date *can* be picked before the start: the start moves back
  /// with it. A book added straight onto "finished" (logging a past read)
  /// starts and finishes on the day it was added, and bounding its finish
  /// by that start left a calendar offering only today — with nothing
  /// saying the start date had to be changed first.
  Future<void> _pickDate(LibraryBook entry, {required bool finish}) async {
    AppHaptics.selection();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? day(DateTime? value) {
      if (value == null) return null;
      final local = value.toLocal();
      return DateTime(local.year, local.month, local.day);
    }

    final started = day(entry.progress.startedAt);
    final finished = day(entry.progress.finishedAt);
    final first = DateTime(1900);
    var last = finish ? today : (entry.isFinished ? finished ?? today : today);
    if (last.isAfter(today)) last = today;
    var initial = (finish ? finished : started) ?? last;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: finish ? 'finished on' : 'started on',
      routeSettings: const RouteSettings(name: 'book_date_picker'),
    );
    if (picked == null || !mounted) return;
    final startMovesBack =
        finish && started != null && picked.isBefore(started);
    await _run(
      'save that date',
      () => LibraryScope.read(context).setDates(
        entry.id,
        startedAt: finish ? (startMovesBack ? picked : null) : picked,
        finishedAt: finish ? picked : null,
      ),
    );
  }

  Widget _ratingRow(LibraryBook entry) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RowLabel('rating'),
          const SizedBox(height: AppSpacing.xs),
          StarRatingInput(
            // A rating kept from before the book left the finished shelf
            // isn't shown as current — it isn't rateable now.
            rating: entry.isFinished ? entry.rating : null,
            onChanged: entry.isFinished
                ? (stars) {
                    AppHaptics.selection();
                    unawaited(
                      _run(
                        'save that rating',
                        () => LibraryScope.read(
                          context,
                        ).rateBookById(entry.id, stars),
                      ),
                    );
                  }
                : null,
          ),
          if (!entry.isFinished)
            Text(
              'finish this book to rate it.',
              style: context.fonts.body(
                fontSize: 12,
                color: colors.secondaryText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _seriesSection(LibraryBook entry, LibraryController library) {
    final seriesId = entry.seriesId;
    final label = library.seriesLabelFor(entry);

    return InfoSection(
      title: 'series',
      rows: [
        _ActionRow(
          label: 'add series',
          onTap: () => showSeriesSelectionSheet(context, entry.id),
        ),
        if (seriesId != null && label != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _RemovableChip(
                  label: label,
                  onRemove: () => _run(
                    'remove that series',
                    () => library.removeFromSeriesById(entry.id),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tagsSection(BookDetailController detail) {
    final colors = context.colors;
    final section = detail.tags;
    final tags = section.data ?? const <BookTag>[];
    final showsList =
        (section.isLoading && !section.hasData) ||
        (section.error != null && !section.hasData) ||
        tags.isNotEmpty;

    return InfoSection(
      title: 'tags',
      rows: [
        _ActionRow(
          label: 'add tags',
          onTap: () => showTagSelectionSheet(context, detail),
        ),
        if (showsList)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: section.isLoading && !section.hasData
                ? _Hint('loading tags…', colors: colors)
                : section.error != null && !section.hasData
                ? _Retry(
                    message: section.error!,
                    onRetry: detail.loadTags,
                    colors: colors,
                  )
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final tag in tags)
                        _TagChip(
                          tag: tag,
                          onRemove: BookDetailController.isPending(tag.id)
                              ? null
                              : () => _run(
                                  'remove that tag',
                                  () => detail.removeTag(tag.id),
                                ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _commentsSection(LibraryBook entry, BookDetailController detail) {
    final colors = context.colors;
    final section = detail.comments;
    final comments = section.data ?? const <BookComment>[];

    Future<void> submit() async {
      final text = _comment.text;
      if (text.trim().isEmpty) return;
      _comment.clear();
      await _run('save that comment', () async {
        final result = await detail.addComment(text);
        if (!result.success && _comment.text.isEmpty) _comment.text = text;
        return result;
      });
    }

    return InfoSection(
      title: 'comments',
      rows: [
        if (section.isLoading && !section.hasData)
          _padded(_Hint('loading comments…', colors: colors))
        else if (section.error != null && !section.hasData)
          _padded(
            _Retry(
              message: section.error!,
              onRetry: detail.loadComments,
              colors: colors,
            ),
          )
        else
          for (final comment in comments)
            _CommentRow(
              comment: comment,
              onEdit: () => _editComment(detail, comment),
              onDelete: () => _deleteComment(detail, comment),
            ),
        _padded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DetailTextField(
                controller: _comment,
                // A DNF is exactly when a reader has something to say
                // about why — ask the question outright.
                hintText: entry.isDnf
                    ? "why didn't you finish it?"
                    : 'write a comment',
                semanticsLabel: 'New comment',
                maxLines: 4,
                maxLength: BookComment.maxLength,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: submit,
                  child: Text(
                    'post',
                    style: context.fonts.interface(
                      fontSize: 13,
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editComment(
    BookDetailController detail,
    BookComment comment,
  ) async {
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _EditCommentDialog(initial: comment.body),
    );
    if (edited == null || !mounted) return;
    await _run(
      'update that comment',
      () => detail.editComment(comment.id, edited),
    );
  }

  Future<void> _deleteComment(
    BookDetailController detail,
    BookComment comment,
  ) async {
    final colors = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'delete comment?',
          style: context.fonts.interface(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        content: Text(
          "this can't be undone.",
          style: context.fonts.body(color: colors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'cancel',
              style: TextStyle(color: colors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('delete', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run('delete that comment', () => detail.deleteComment(comment.id));
  }

  Widget _aboutSection(
    Book book,
    BookDetailController detail, {
    String? seriesLabel,
  }) {
    final colors = context.colors;
    final section = detail.book;
    // Publisher, published, pages and language are in the facts strip at
    // the top; these are the details a reader looks up rather than scans.
    final facts = <(String, String)>[
      if (seriesLabel != null) ('series', seriesLabel),
      if (book.categories.isNotEmpty) ('genre', book.categories.join(', ')),
      if (book.isbn13 ?? book.isbn10 case final isbn?) ('isbn', isbn),
      if (book.averageRating case final rating?)
        (
          'google books rating',
          '$rating / 5${book.ratingsCount == null ? '' : ' (${book.ratingsCount} ratings)'}',
        ),
    ];

    return InfoSection(
      title: 'about',
      rows: [
        _padded(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (book.description case final blurb?)
                _Blurb(text: blurb, colors: colors)
              else if (!section.isLoading)
                _Hint('no blurb available for this book.', colors: colors),
              if (section.isLoading) ...[
                if (book.description != null)
                  const SizedBox(height: AppSpacing.sm),
                _Hint('loading more from google books…', colors: colors),
              ],
              if (section.error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _Retry(
                  message: section.error!,
                  onRetry: detail.loadDetails,
                  colors: colors,
                ),
              ],
            ],
          ),
        ),
        for (final (label, value) in facts)
          MergeSemantics(
            child: _padded(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: Text(
                      label,
                      style: context.fonts.interface(
                        fontSize: 12,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: context.fonts.body(
                        fontSize: 14,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static Widget _padded(Widget child) =>
      Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child);
}

extension on DetailTextField {
  /// Attaches a focus node without widening [DetailTextField]'s own API —
  /// only the progress fields care whether they're focused.
  Widget withFocus(FocusNode node) => Focus(
    focusNode: node,
    skipTraversal: true,
    canRequestFocus: false,
    child: this,
  );
}

/// A small caption inside a row ("progress", "rating"), with an optional
/// right-aligned readout.
/// One tappable date on the book page — "started" over "9.1.26", or "—"
/// with nothing set. A single button node to screen readers.
class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  /// `m.d.yy`, no leading zeros — the app's one date format.
  static String format(DateTime date) {
    final local = date.toLocal();
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '${local.month}.${local.day}.$year';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = date;
    return Semantics(
      button: true,
      label:
          '$label ${value == null ? 'not set' : format(value)}. '
          'Double tap to change.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: context.fonts.body(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value == null ? '—' : format(value),
                      style: context.fonts.interface(
                        fontSize: 15,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.edit_calendar_outlined,
                    size: 16,
                    color: colors.secondaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final readout = trailing;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: context.fonts.body(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ),
        if (readout != null)
          ExcludeSemantics(
            child: Text(
              readout,
              style: context.fonts.interface(
                fontSize: 13,
                color: colors.accent,
              ),
            ),
          ),
      ],
    );
  }
}

/// Cover, title, author, where the reader is with the book, and which
/// edition they own — the one block a reader needs to recognise the page.
class _Heading extends StatelessWidget {
  const _Heading({required this.entry, required this.book});

  final LibraryBook entry;

  /// Already the reader's own edition, when they picked one.
  final Book book;

  /// "reading · 78%", "to read", "finished", "did not finish · stopped at
  /// 34%" — the shelf and, where it means something, how far.
  static String status(LibraryBook entry) {
    final completion = entry.completion;
    final percent = completion == null
        ? null
        : '${(completion * 100).round()}%';
    final page = entry.currentPage == 0 ? null : 'page ${entry.currentPage}';
    return switch (entry.status) {
      ReadingStatus.reading =>
        'reading${percent != null
            ? ' · $percent'
            : page != null
            ? ' · $page'
            : ''}',
      ReadingStatus.toBeRead => 'to read',
      ReadingStatus.finished => 'finished',
      ReadingStatus.dnf =>
        entry.currentPage == 0
            ? 'did not finish'
            : 'did not finish · stopped at ${percent ?? page}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final owned = entry.ownedEdition;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: BookCover(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                isbn: book.isbn13 ?? book.isbn10,
                rereadCount: entry.rereadCount,
                finished: entry.isFinished,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  book.title,
                  style: context.fonts.bookTitle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              if (book.subtitle case final subtitle?) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.fonts.bookTitle(
                    fontSize: 15,
                    height: 1.25,
                    color: colors.secondaryText,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                book.author,
                style: context.fonts.body(
                  fontSize: 14,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                status(entry),
                style: context.fonts.interface(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
              if (owned != null) ...[
                const SizedBox(height: 2),
                Text(
                  'you own the '
                  '${owned.format == EditionFormat.ebook ? 'ebook' : 'physical edition'}'
                  '${owned.year == null ? '' : ' (${owned.year})'}',
                  style: context.fonts.interface(
                    fontSize: 12,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Pages, published, publisher, language — a row of small label-over-value
/// cells on one surface, the details a reader scans for first. Cells only
/// appear for what's known; while Google Books is still being asked and
/// nothing is known yet, the strip says so instead of rendering empty.
class _FactsStrip extends StatelessWidget {
  const _FactsStrip({required this.book, required this.loading});

  final Book book;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final facts = <(String, String)>[
      if (book.pageCount case final pages?) ('pages', '$pages'),
      if (book.publishedDate case final date?)
        ('published', formatPublishedDate(date)),
      if (book.publisher case final publisher?) ('publisher', publisher),
      if (book.language case final language?)
        ('language', language.toUpperCase()),
    ];

    if (facts.isEmpty) {
      return loading
          ? _Hint('loading details…', colors: colors)
          : const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (label, value) in facts)
            MergeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: context.fonts.interface(
                        fontSize: 11,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.fonts.body(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single entry point to the editions gallery: a settings-style row
/// with the same shape every time — "editions" with how many there are on
/// the right, and, when the reader owns one, which one on its own line
/// underneath. (The count used to be *replaced* by "you own the ebook" once
/// editions had loaded, so the same row read differently from one visit to
/// the next.) The owned edition comes from the shelf row itself, so that
/// line is there from the first frame, not only after editions load.
class _EditionsRow extends StatelessWidget {
  const _EditionsRow({
    required this.section,
    required this.owned,
    required this.onTap,
  });

  final DetailSection<List<BookEdition>> section;
  final BookEdition? owned;
  final VoidCallback onTap;

  /// The right-hand readout: always about the list, never the owned one.
  String _count() {
    final editions = section.data;
    if (editions == null) {
      if (section.isLoading) return 'loading';
      if (section.error != null) return 'unavailable';
      return '';
    }
    return editions.isEmpty ? 'none found' : '${editions.length}';
  }

  /// "ebook · Penguin · 2010".
  static String describeOwned(BookEdition edition) => [
    edition.format == EditionFormat.ebook ? 'ebook' : 'physical',
    ?edition.publisher,
    ?edition.year,
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = _count();
    final ownedEdition = owned;
    final ownedLine = ownedEdition == null ? null : describeOwned(ownedEdition);

    return Semantics(
      button: true,
      label: [
        'Editions',
        if (count.isNotEmpty) count,
        if (ownedLine != null) 'yours: $ownedLine',
      ].join(', '),
      hint: 'Opens every ebook and physical edition',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 20,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'editions',
                        style: context.fonts.body(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                      if (ownedLine != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'yours: $ownedLine',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.fonts.interface(
                            fontSize: 12,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // A fixed-width slot, so the chevron doesn't jump as the
                // readout goes from a spinner to a number.
                SizedBox(
                  width: 80,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: section.isLoading && !section.hasData
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.secondaryText,
                            ),
                          )
                        : Text(
                            count,
                            style: context.fonts.body(
                              fontSize: 14,
                              color: colors.secondaryText,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.onRemove});

  final BookTag tag;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: onRemove == null ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tag.tag,
              style: context.fonts.interface(
                fontSize: 13,
                color: colors.primaryText,
              ),
            ),
            Semantics(
              // Its own node, so "Remove tag sci-fi" isn't merged into the
              // chip's text and read as one unactionable label.
              container: true,
              button: true,
              label: 'Remove tag ${tag.tag}',
              excludeSemantics: true,
              child: InkResponse(
                onTap: onRemove,
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

/// [_TagChip]'s own look, generalised to any label — used for the single
/// series chip, where there's no `BookTag`-shaped row to carry.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: onRemove == null ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: context.fonts.interface(
                fontSize: 13,
                color: colors.primaryText,
              ),
            ),
            Semantics(
              container: true,
              button: true,
              label: 'Remove $label',
              excludeSemantics: true,
              child: InkResponse(
                onTap: onRemove,
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

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
  });

  final BookComment comment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static String _date(DateTime at) {
    final local = at.toLocal();
    return '${local.month}.${local.day}.${local.year % 100}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pending = BookDetailController.isPending(comment.id);

    return Opacity(
      opacity: pending ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment.body,
              style: context.fonts.body(
                fontSize: 14,
                height: 1.5,
                color: colors.primaryText,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_date(comment.createdAt)}'
                    '${comment.isEdited ? ' · edited' : ''}'
                    '${pending ? ' · saving…' : ''}',
                    style: context.fonts.interface(
                      fontSize: 11,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit comment',
                  visualDensity: VisualDensity.compact,
                  onPressed: pending ? null : onEdit,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete comment',
                  visualDensity: VisualDensity.compact,
                  onPressed: pending ? null : onDelete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({required this.initial});

  final String initial;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'edit comment',
        style: context.fonts.interface(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.primaryText,
        ),
      ),
      content: DetailTextField(
        controller: _controller,
        hintText: 'comment',
        semanticsLabel: 'Comment',
        maxLines: 6,
        maxLength: BookComment.maxLength,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel', style: TextStyle(color: colors.secondaryText)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('save', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}

/// The blurb, clamped to a few lines with a "more" toggle — some run to
/// several screens.
class _Blurb extends StatefulWidget {
  const _Blurb({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  State<_Blurb> createState() => _BlurbState();
}

class _BlurbState extends State<_Blurb> {
  static const _collapsedLines = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = context.fonts.body(
      fontSize: 14,
      height: 1.6,
      color: widget.colors.primaryText,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? null : TextOverflow.fade,
            ),
            if (overflows)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 32),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'less' : 'more',
                  semanticsLabel: _expanded
                      ? 'Show less of the description'
                      : 'Show the full description',
                  style: context.fonts.interface(
                    fontSize: 13,
                    color: widget.colors.accent,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A row that opens something — the same shape as settings' own
/// `SettingsRow` (label, chevron), but with no leading icon: these sit
/// inside an already-titled [InfoSection] ("tags", "series"), so an icon
/// would repeat what the caption already says.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: context.fonts.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled row with an optional value on the right and a chevron — the
/// shelf row and "read again".
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    super.key,
    required this.label,
    this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = this.value;
    return Semantics(
      button: true,
      label: value == null ? label : '$label, $value',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: context.fonts.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: context.fonts.body(
                        fontSize: 14,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.fonts.interface(fontSize: 13, color: colors.secondaryText),
  );
}

/// A section's load failure: the friendly message, and a retry.
class _Retry extends StatelessWidget {
  const _Retry({
    required this.message,
    required this.onRetry,
    required this.colors,
  });

  final String message;
  final Future<void> Function() onRetry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: context.fonts.body(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            'try again',
            style: context.fonts.interface(fontSize: 13, color: colors.accent),
          ),
        ),
      ],
    ),
  );
}

/// The book was deleted (by a command, on another device) while this page
/// was open, or never existed.
class _Gone extends StatelessWidget {
  const _Gone({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      child: Text(
        'no longer on your shelf.',
        textAlign: TextAlign.center,
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      ),
    ),
  );
}
