import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/library_book.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';
import '../widgets/book_cover.dart';
import '../widgets/book_tile.dart';

/// The reader's shelf: in-progress books in a cover grid, with finished
/// books in their own section below.
///
/// Purely a view — it reads [LibraryController] out of [LibraryScope]
/// and rebuilds when it notifies, so a progress update from the log page
/// shows up here with no refresh of any kind.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  /// The floating bottom bar's footprint, so the last row of covers
  /// isn't hidden behind it — same constant the streaks page uses.
  static const _barFootprint = 108.0;

  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: load() notifies synchronously
    // to raise its loading flag, and notifying mid-build is illegal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LibraryScope.read(context).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = LibraryScope.of(context);
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.surface,
          onRefresh: controller.load,
          child: CustomScrollView(
            // Always scrollable so pull-to-refresh works even when the
            // shelf is empty or errored.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),
              ..._body(controller),
              const SliverToBoxAdapter(
                child: SizedBox(height: _barFootprint + AppSpacing.md),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(LibraryController controller) {
    // Errors and the first-load spinner replace the shelf; once books
    // are on screen a failed refresh leaves them there rather than
    // blanking a working page.
    if (controller.errorMessage != null && controller.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Message(
            text: controller.errorMessage!,
            actionLabel: 'Try again',
            onAction: controller.load,
          ),
        ),
      ];
    }
    if (controller.isLoading && controller.isEmpty) {
      return const [
        SliverToBoxAdapter(child: _Message(text: 'Loading your library…')),
      ];
    }
    if (controller.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: _Message(
            text: 'Nothing here yet.\nType "start <book>" on the log page.',
          ),
        ),
      ];
    }

    final reading = controller.inProgress;
    final finished = controller.finished;

    return [
      if (reading.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionLabel('reading')),
        _BookGrid(entries: reading),
      ],
      if (finished.isNotEmpty) ...[
        const SliverToBoxAdapter(child: _SectionLabel('finished')),
        _BookGrid(entries: finished, dimmed: true),
      ],
    ];
  }
}

/// A responsive cover grid — a fixed max tile width rather than a fixed
/// column count, so it holds up from a small phone to a tablet.
class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.entries, this.dimmed = false});

  final List<LibraryBook> entries;
  final bool dimmed;

  static const _maxTileWidth = 150.0;

  /// Room under the cover for title, author, bar, and label. Fixed so
  /// tiles line up; the text inside ellipsizes to fit.
  static const _textExtent = 86.0;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent - AppSpacing.xl * 2;
          final columns = (width / _maxTileWidth).ceil().clamp(2, 5);
          final tileWidth = (width - AppSpacing.md * (columns - 1)) / columns;
          final tileHeight = tileWidth / BookCover.aspectRatio + _textExtent;

          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: tileWidth / tileHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final entry = entries[index];
              return BookTile(
                // Keyed on the progress row so Flutter reuses the right
                // element when a book moves between sections.
                key: ValueKey(entry.id),
                entry: entry,
                cover: BookCover(
                  title: entry.book.title,
                  author: entry.book.author,
                  coverUrl: entry.book.coverUrl,
                  dimmed: dimmed,
                ),
              );
            }, childCount: entries.length),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: _SectionLabel('library', large: true),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        large ? 0 : AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: large ? 20 : 16,
          fontWeight: FontWeight.w600,
          color: large ? colors.primaryText : colors.secondaryText,
        ),
      ),
    );
  }
}

/// Empty / loading / error state, all in the same centered slot so the
/// page doesn't reflow as it moves between them.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = actionLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              height: 1.6,
              color: colors.secondaryText,
            ),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onAction,
              child: Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
