import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/memory.dart';
import '../controllers/memory_controller.dart';
import '../memory_scope.dart';

/// Gap between one book's notes and the next book's heading — same
/// value the streak journal uses between one day and the next.
const _groupSpacing = AppSpacing.lg;

/// Gap between one note and the next about the same book — same value
/// the streak journal uses between one entry and the next in a day.
const _entrySpacing = AppSpacing.sm;

/// The reader's saved notes on how a book made them feel — what "cactus
/// pro"'s `remember` command writes, and what `recommend` grounds its
/// picks in.
///
/// Styled as a journal, the same way the streak tab is: a book title
/// reads exactly like a streak day's date label, and the notes under it
/// read exactly like a streak day's command lines. Memories group by
/// book rather than by day — a note without one groups under "general",
/// the same wording [Memory.bookTitle]'s own doc comment uses for it —
/// with the most recently added-to book first, and a book's own notes
/// oldest first underneath it, so both read top-to-bottom like a story.
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
  /// The floating bottom bar's total footprint (bar height + its own
  /// gap + the name label + its margin from the screen edge) — see
  /// bottom_switcher.dart's _outerHeight (70) and root_shell.dart. Same
  /// value every other tab uses.
  static const _barFootprint = 108.0;

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
    // `of`, not `read`: the list itself is rendered below, so this page
    // has to rebuild whenever `remember`/`forget` changes it — unlike
    // the one-off `load()` kick in `initState`.
    final memory = MemoryScope.of(context);

    return Scaffold(
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              bottom: _MemoryPageState._barFootprint,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TopBar(title: 'memory'),
                const SizedBox(height: AppSpacing.lg),
                _MemoryJournal(controller: memory),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading / error / empty / journal, in that order of what to show. A
/// failed load must not look like an empty one — see CLAUDE.md
/// § Errors, logging and startup.
class _MemoryJournal extends StatelessWidget {
  const _MemoryJournal({required this.controller});

  final MemoryController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (controller.isLoading && controller.memories.isEmpty) {
      return Text(
        'loading memories…',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          color: colors.secondaryText,
        ),
      );
    }

    final error = controller.errorMessage;
    if (error != null && controller.memories.isEmpty) {
      return Text(
        error,
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.5,
          color: colors.secondaryText,
        ),
      );
    }

    if (controller.memories.isEmpty) {
      return Text(
        'nothing remembered yet — on cactus pro, say something like '
        '"i loved the ending of dune" and it\'ll show up here, and '
        'shape what recommend suggests next.',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          height: 1.4,
          color: colors.secondaryText,
        ),
      );
    }

    // Grouped here rather than by `MemoryController`, the same way the
    // streak journal groups its own controller's flat list by day
    // rather than asking `StreaksController` to. `groups[key] ??= []`
    // builds fresh lists, so the sorting below never touches
    // `controller.memories` itself.
    final groups = <String, List<Memory>>{};
    for (final memory in controller.memories) {
      (groups[memory.bookTitle ?? 'general'] ??= []).add(memory);
    }
    final ordered = groups.entries.toList()
      ..sort((a, b) => _latest(b.value).compareTo(_latest(a.value)));
    for (final group in ordered) {
      group.value.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, group) in ordered.indexed) ...[
          if (i > 0) const SizedBox(height: _groupSpacing),
          _MemoryGroup(
            title: group.key,
            memories: group.value,
            onForget: controller.forget,
          ),
        ],
      ],
    );
  }

  static DateTime _latest(List<Memory> memories) =>
      memories.map((m) => m.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// One book's title, then every note about it — oldest first, the order
/// they were actually remembered in, so a book's own notes read
/// top-to-bottom like the rest of the story.
class _MemoryGroup extends StatelessWidget {
  const _MemoryGroup({
    required this.title,
    required this.memories,
    required this.onForget,
  });

  final String title;
  final List<Memory> memories;
  final Future<MemoryActionResult> Function(String id) onForget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same face, size and color the streak journal's own date label
        // uses — a book name is this journal's "day".
        Text(
          title,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: _entrySpacing),
        for (final (i, memory) in memories.indexed) ...[
          if (i > 0) const SizedBox(height: _entrySpacing),
          _MemoryLine(memory: memory, onForget: () => onForget(memory.id)),
        ],
      ],
    );
  }
}

/// One remembered note, in the exact face and size the streak journal's
/// own command lines use, plus a small "forget" affordance at the end
/// of the line.
class _MemoryLine extends StatelessWidget {
  const _MemoryLine({required this.memory, required this.onForget});

  final Memory memory;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = memory.bookTitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // One node for the whole note — "Dune. I loved the ending."
          // — not an unlabelled fragment; the delete button keeps its
          // own node as a sibling outside this subtree.
          child: Semantics(
            container: true,
            excludeSemantics: true,
            label: title == null ? memory.note : '$title. ${memory.note}',
            child: Text(
              memory.note,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                height: 1.5,
                color: colors.primaryText,
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Forget this memory',
          child: IconButton(
            onPressed: onForget,
            icon: Icon(Icons.close, size: 16, color: colors.secondaryText),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }
}
