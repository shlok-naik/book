import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/memory.dart';
import '../controllers/memory_controller.dart';
import '../memory_scope.dart';

/// The reader's saved notes on how a book made them feel — what "cactus
/// pro"'s `remember` command writes, and what `recommend` grounds its
/// picks in.
///
/// A whole tab rather than a section of a profile page: these are the
/// reader's own words about their own reading, and they were previously
/// squeezed under a subscription card that had nothing to do with them.
/// The account material that used to share that page now lives behind
/// the gear in [TopBar].
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  /// Room at the bottom for the floating tab bar to sit over, so the
  /// last memory in a full list isn't stuck underneath it.
  static const _barFootprint = 130.0;

  @override
  void initState() {
    super.initState();
    // `read`, not `of`: a one-off kick of the fetch, not a rebuild
    // dependency — `build` below reads the controller through
    // `MemoryScope.of` instead, so this page still rebuilds once the
    // fetch resolves.
    //
    // Deferred to the post-frame callback: `MemoryScope` wraps the
    // whole app, so a `notifyListeners()` fired synchronously from here
    // — still inside the very first build — would try to rebuild an
    // ancestor that is itself mid-mount (see `HomePage.initState`'s own
    // copy of this reasoning).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(MemoryScope.read(context).load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // `of`, not `read`: the list itself is rendered below, so this page
    // has to rebuild whenever `remember`/`forget` changes it — unlike
    // the one-off `load()` kick in `initState`.
    final memory = MemoryScope.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          // Same insets as the streaks and library headers, so all four
          // tabs' gears sit at the exact same position.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TopBar(title: 'memory'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(child: _MemoryList(controller: memory)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading / error / empty / list, in that order of what to show. A
/// failed load must not look like an empty one — see CLAUDE.md
/// § Errors, logging and startup.
class _MemoryList extends StatelessWidget {
  const _MemoryList({required this.controller});

  final MemoryController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (controller.isLoading && controller.memories.isEmpty) {
      return Text(
        'loading memories…',
        style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
      );
    }

    final error = controller.errorMessage;
    if (error != null && controller.memories.isEmpty) {
      return Text(
        error,
        style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
      );
    }

    if (controller.memories.isEmpty) {
      return Text(
        'Nothing remembered yet. On cactus pro, say something like '
        '"I loved the ending of Dune" and it\'ll show up here — and '
        'shape what "recommend" suggests next.',
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.4,
          color: colors.secondaryText,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: _MemoryPageState._barFootprint),
      itemCount: controller.memories.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final memory = controller.memories[index];
        return _MemoryRow(
          memory: memory,
          onDelete: () => controller.forget(memory.id),
        );
      },
    );
  }
}

/// One remembered note — the book it's about (if any), then the note
/// itself, with a delete affordance. One [Semantics] node for the whole
/// row: a screen reader should read "Dune. I loved the ending." as a
/// single thing, not as two unlabelled fragments.
class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.memory, required this.onDelete});

  final Memory memory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = memory.bookTitle;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            // The note and its book title are one thought, so they are
            // one node: "Dune. The ending gutted me." — not a title
            // fragment followed by an orphaned sentence. Scoped to the
            // text alone rather than the whole row, so the delete
            // button beside it keeps its own button node.
            child: Semantics(
              container: true,
              excludeSemantics: true,
              label: title == null ? memory.note : '$title. ${memory.note}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  Text(
                    memory.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Forget this memory',
            child: IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.close, size: 18, color: colors.secondaryText),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}
