import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/numbers.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/widgets/book_cover.dart';
import '../../../logging/presentation/widgets/confirmation_pill.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../paywall/presentation/pro_gate.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/year_in_books.dart';

/// Hands a rendered card to the platform's share sheet. Swapped for a fake
/// in tests.
typedef CardSharer = Future<void> Function(List<int> png, String fileName);

Future<void> _sharePng(List<int> png, String fileName) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png', name: fileName)],
    ),
  );
}

/// Opens [YearInBooksPage]. The one way it should be pushed, so it always
/// carries its route name.
Future<void> openYearInBooks(
  BuildContext context, {
  PurchasesService? purchases,
  CardSharer? share,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'year_in_books'),
      builder: (_) => YearInBooksPage(purchases: purchases, share: share),
    ),
  );
}

/// "your year in books" — cactus pro. The reader's year on one story-sized
/// card ([YearInBooksCard]): books and pages read, their favourite, their
/// longest, their top genre and the covers of their latest finishes, ready
/// to share as an image. Built from the shelf alone, like the stats page.
class YearInBooksPage extends StatefulWidget {
  const YearInBooksPage({super.key, this.purchases, this.share, this.now});

  final PurchasesService? purchases;
  final CardSharer? share;

  /// Tests pin the year.
  final DateTime? now;

  @override
  State<YearInBooksPage> createState() => _YearInBooksPageState();
}

class _YearInBooksPageState extends State<YearInBooksPage>
    with ProGateState<YearInBooksPage> {
  @override
  PurchasesService? get purchasesOverride => widget.purchases;

  @override
  PaywallFeature get paywallFeature => PaywallFeature.expression;

  final _boundary = GlobalKey();
  bool _sharing = false;
  String? _message;

  Future<void> _share(YearInBooks year) async {
    if (_sharing) return;
    AppHaptics.selection();
    setState(() {
      _sharing = true;
      _message = null;
    });
    try {
      // Covers that haven't downloaded yet would be captured as blanks.
      await Future.wait([
        for (final entry in year.finished)
          if (entry.displayBook.coverUrl case final url?)
            precacheImage(NetworkImage(url), context, onError: (_, _) {}),
      ]);
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card not laid out.');
      final image = await boundary.toImage(
        pixelRatio: YearInBooksCard.exportWidth / YearInBooksCard.width,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Card could not be encoded.');
      await (widget.share ?? _sharePng)(
        bytes.buffer.asUint8List(),
        'cactus-${year.year}.png',
      );
      AppHaptics.accepted();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'YearInBooksPage',
        'Sharing the year card failed.',
        error: error,
        stackTrace: stackTrace,
      );
      AppHaptics.rejected();
      if (mounted) setState(() => _message = "Couldn't share card.");
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final year = YearInBooks.from(library.books, now: widget.now);

    final String label;
    VoidCallback? onPressed;
    if (!isProUnlocked) {
      label = 'unlock with cactus pro';
      onPressed = unlockBusy ? null : unlockPro;
    } else if (year.isEmpty) {
      label = 'finish a book to share your year';
    } else if (_sharing) {
      label = 'getting it ready…';
    } else {
      label = 'share';
      onPressed = () => unawaited(_share(year));
    }

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
              const SettingsHeader(title: 'your year'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: YearInBooksCard(year: year),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_message case final message?) ...[
                ConfirmationPill(
                  message: message,
                  tone: ConfirmationTone.failure,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FilledButton.icon(
                key: const ValueKey('year-card-share'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: onPressed,
                icon: Icon(
                  isProUnlocked ? Icons.ios_share : Icons.lock_outline,
                  size: 18,
                ),
                label: Text(
                  label,
                  style: context.fonts.interface(fontSize: 15),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card itself: a 9:16 story, drawn at [width] logical pixels and
/// exported at [exportWidth]. Uses the reader's theme, accent and fonts.
class YearInBooksCard extends StatelessWidget {
  const YearInBooksCard({super.key, required this.year});

  final YearInBooks year;

  static const width = 360.0;
  static const height = 640.0;
  static const exportWidth = 1080.0;

  static const _coverHeight = 112.0;

  static const _months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fonts = context.fonts;
    final noun = year.books == 1 ? 'book' : 'books';
    final pages = formatThousands(year.pages);

    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: fonts.interface(fontSize: 11, color: colors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: fonts.bookTitle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );

    String titled(LibraryBook entry) =>
        '${entry.displayBook.title} — ${entry.displayBook.author}';

    final favourite = year.favourite;
    return Semantics(
      label:
          'Your ${year.year} in books: ${year.books} $noun, $pages pages.'
          '${favourite == null ? '' : ' Favourite: ${favourite.book.title}.'}',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.primaryText, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'cactus',
                  style: fonts.interface(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
                const Spacer(),
                Text(
                  'my ${year.year} in books',
                  style: fonts.interface(
                    fontSize: 12,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${year.books}',
                style: fonts.interface(
                  fontSize: 88,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
            ),
            Text(
              '$noun finished · $pages pages',
              style: fonts.interface(fontSize: 14, color: colors.accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: _coverHeight,
              child: Row(
                children: [
                  for (final (i, entry) in year.finished.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: _coverHeight * BookCover.aspectRatio,
                      child: BookCover(
                        title: entry.displayBook.title,
                        author: entry.displayBook.author,
                        coverUrl: entry.displayBook.coverUrl,
                        isbn:
                            entry.displayBook.isbn13 ??
                            entry.displayBook.isbn10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: AppSpacing.md),
            if (favourite != null)
              fact(
                'favourite',
                '${titled(favourite)} · '
                    '${formatCompactNumber(favourite.rating!)}★',
              ),
            if (year.longest case final longest?)
              fact(
                'longest',
                '${longest.displayBook.title} · ${longest.pageCount} pages',
              ),
            if (year.topGenre case final genre?)
              fact('top genre', genre.toLowerCase()),
            if (year.busiestMonth case final month?)
              fact('busiest month', _months[month - 1]),
            if (year.averageRating case final average?)
              fact(
                'average rating',
                '${formatCompactNumber(roundToHalf(average))} / 5',
              ),
            const Spacer(),
            Text(
              'tracked with cactus',
              style: fonts.interface(fontSize: 11, color: colors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
