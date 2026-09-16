import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/formatting/numbers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/data/open_library_client.dart';
import '../../../library/domain/edition_filter.dart';
import '../../../library/domain/library_exception.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../../../library/presentation/widgets/info_section.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../widgets/volume_shelf_actions.dart';

/// Opens [VolumeDetailPage] for a Google Books result. The one way it should
/// be pushed, so the route carries its analytics name.
Future<void> openVolumeDetails(BuildContext context, GoogleBook volume) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'volume_detail'),
      builder: (_) => VolumeDetailPage(volume: volume),
    ),
  );
}

/// Everything Google Books knows about a book the reader found in search —
/// the same layout as the shelf's own book page (heading, facts strip,
/// about), but read-only and straight from Google: nothing is cached or
/// added until the reader taps one of [VolumeShelfActions]' buttons.
///
/// A search result is a trimmed record, so the page shows it at once and
/// then fetches the full volume (complete blurb, categories, ratings). If
/// that fetch fails, the search result's own data stays up with a note.
class VolumeDetailPage extends StatefulWidget {
  const VolumeDetailPage({super.key, required this.volume});

  final GoogleBook volume;

  @override
  State<VolumeDetailPage> createState() => _VolumeDetailPageState();
}

class _VolumeDetailPageState extends State<VolumeDetailPage> {
  static const _messageLifetime = Duration(seconds: 3);

  late GoogleBook _volume = widget.volume;
  bool _loading = true;
  String? _loadError;

  String? _message;
  ConfirmationTone _tone = ConfirmationTone.neutral;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // An Open Library result is already the whole record.
    if (OpenLibraryClient.isOpenLibraryId(widget.volume.id)) {
      setState(() => _loading = false);
      return;
    }
    try {
      final full = await LibraryScope.read(
        context,
      ).lookup.googleBooks.fetchVolume(widget.volume.id);
      if (!mounted) return;
      setState(() {
        _volume = full;
        _loading = false;
      });
    } on LibraryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'VolumeDetailPage',
        'Loading the full volume failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Couldn't load details.";
      });
    }
  }

  void _showResult(LibraryActionResult result) {
    final message = result.message;
    if (message == null || !mounted) return;
    setState(() {
      _message = message;
      _tone = result.success
          ? ConfirmationTone.success
          : ConfirmationTone.failure;
    });
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final volume = _volume;
    final blurb = volume.description == null
        ? null
        : plainTextFromHtml(volume.description!);
    final facts = <(String, String)>[
      if (volume.pageCount case final pages?) ('pages', '$pages'),
      if (volume.publishedDate case final date?)
        ('published', formatPublishedDate(date)),
      if (volume.publisher case final publisher?) ('publisher', publisher),
      if (volume.language case final language?)
        ('language', language.toUpperCase()),
    ];
    final isbn = volume.isbn13 ?? volume.isbn10;
    final rating = volume.averageRating;

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
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: BookCover(
                            title: volume.title,
                            author: volume.authorLine,
                            coverUrl: volume.thumbnailUrl,
                            isbn: isbn,
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
                                  volume.title,
                                  style: context.fonts.bookTitle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: colors.primaryText,
                                  ),
                                ),
                              ),
                              if (volume.subtitle case final subtitle?)
                                Text(
                                  subtitle,
                                  style: context.fonts.body(
                                    fontSize: 14,
                                    color: colors.secondaryText,
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                volume.authorLine,
                                style: context.fonts.body(
                                  fontSize: 15,
                                  color: colors.primaryText,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                OpenLibraryClient.isOpenLibraryId(volume.id)
                                    ? 'from open library'
                                    : 'from google books',
                                style: context.fonts.interface(
                                  fontSize: 12,
                                  color: colors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (facts.isNotEmpty) _FactsStrip(facts: facts),
                    if (_loading || _loadError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _loading ? 'loading details…' : _loadError!,
                        style: context.fonts.interface(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    VolumeShelfActions(volume: volume, onResult: _showResult),
                    const SizedBox(height: AppSpacing.lg),
                    InfoSection(
                      title: 'about',
                      rows: [
                        if (blurb != null && blurb.isNotEmpty)
                          _AboutText(blurb),
                        if (volume.categories.isNotEmpty)
                          _AboutRow('genre', volume.categories.join(', ')),
                        if (isbn != null) _AboutRow('isbn', isbn),
                        if (rating != null)
                          _AboutRow(
                            'google rating',
                            '${formatCompactNumber(rating)} / 5'
                                '${volume.ratingsCount == null ? '' : ' · ${volume.ratingsCount} ratings'}',
                          ),
                        if (blurb == null &&
                            volume.categories.isEmpty &&
                            isbn == null &&
                            rating == null)
                          const _AboutText(
                            "google books doesn't say much about this one.",
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: ConfirmationPill(message: message, tone: _tone),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactsStrip extends StatelessWidget {
  const _FactsStrip({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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

class _AboutText extends StatelessWidget {
  const _AboutText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Text(
      text,
      style: context.fonts.body(
        fontSize: 14,
        height: 1.5,
        color: context.colors.primaryText,
      ),
    ),
  );
}

class _AboutRow extends StatelessWidget {
  const _AboutRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: context.fonts.interface(
                  fontSize: 13,
                  color: colors.secondaryText,
                ),
              ),
            ),
            Expanded(
              child: Text(
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
    );
  }
}
