import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../paywall/presentation/pro_gate.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/memory.dart';
import '../controllers/memory_controller.dart';
import '../memory_scope.dart';

/// Gap between one book's notes and the next book's heading — same
/// value the streak journal uses between one day and the next.
const _groupSpacing = AppSpacing.lg;

/// Gap between one note and the next about the same book — same value
/// the streak journal uses between one entry and the next in a day.
const _entrySpacing = AppSpacing.sm;

/// A note's own line box — `fontSize: 16 * height: 1.5`, the same style
/// the streak journal's command lines use. `_MemoryLine`'s delete
/// affordance is boxed to exactly this height rather than left to
/// `IconButton`'s own (larger) minimum tap size, so a note's row is
/// exactly as tall as a bare line of text — matching the streak
/// journal's rows, which have nothing trailing them at all — instead of
/// quietly taller and throwing off the rhythm `_entrySpacing` is
/// supposed to guarantee between one line and the next.
const _noteLineHeight = 16 * 1.5;

/// Opens [MemoryPage]. The one way it should be pushed — from settings'
/// profile section, or a bare `memory` typed on the add tab — so the route
/// always carries its analytics name.
Future<void> openMemoryPage(
  BuildContext context, {
  PurchasesService? purchases,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'memory'),
      builder: (_) => MemoryPage(purchases: purchases),
    ),
  );
}

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
/// A page pushed from settings' **profile** section (see
/// [openMemoryPage]), wearing [SettingsHeader] like every other page
/// opened from there. It used to be a tab; the search tab took its slot.
///
/// A cactus pro page, gated the way the stats page's journal is: a free
/// reader who opens the page (or types `memory` on the add tab) sees a
/// faded preview of invented notes and "cactus pro unlocks your full
/// reading memory", and tapping it opens the paywall on the memory
/// chapter ([PaywallFeature.memory]) — see [_LockedMemory]. It used to
/// skip the page entirely and throw the paywall up over the add tab, so a
/// free reader never saw what the tab even was.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, this.purchases});

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> with ProGateState<MemoryPage> {
  @override
  PurchasesService? get purchasesOverride => widget.purchases;

  @override
  PaywallFeature get paywallFeature => PaywallFeature.memory;

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
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          // Same insets as settings, so the heading doesn't move when this
          // page is pushed over it.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsHeader(title: 'memory'),
                const SizedBox(height: AppSpacing.lg),
                if (isProUnlocked)
                  _MemoryJournal(controller: memory)
                else
                  _LockedMemory(busy: unlockBusy, onTap: unlockPro),
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
        style: context.fonts.interface(
          fontSize: 14,
          color: colors.secondaryText,
        ),
      );
    }

    final error = controller.errorMessage;
    if (error != null && controller.memories.isEmpty) {
      return Text(
        error,
        style: context.fonts.body(
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
        style: context.fonts.interface(
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

/// What a free reader sees in place of their memories: the same
/// [_MemoryGroup] layout the real journal renders, faded and inert, over
/// invented notes rather than anything of the reader's own — plus the line
/// naming the way out. The whole block is one tap target, the exact
/// treatment the stats page's `_LockedJournal` gives the reading journal.
class _LockedMemory extends StatelessWidget {
  const _LockedMemory({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  static final _preview = [
    (
      title: 'The Hobbit',
      memories: [
        Memory(
          id: 'preview-1',
          note: 'felt like a warm blanket on a cold night',
          bookTitle: 'The Hobbit',
          createdAt: DateTime(2026, 9, 12),
        ),
      ],
    ),
    (
      title: 'Dune',
      memories: [
        Memory(
          id: 'preview-2',
          note: 'the desert scenes stayed with me for days',
          bookTitle: 'Dune',
          createdAt: DateTime(2026, 9, 10),
        ),
        Memory(
          id: 'preview-3',
          note: 'slow start, but the ending was worth it',
          bookTitle: 'Dune',
          createdAt: DateTime(2026, 9, 11),
        ),
      ],
    ),
  ];

  static Future<MemoryActionResult> _inert(String _) async =>
      const MemoryActionResult.failure('');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label:
          'Reading memory, locked. Upgrade to cactus pro to unlock. '
          'Double tap to upgrade.',
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('locked-memory'),
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: 0.4,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, group) in _preview.indexed) ...[
                      if (i > 0) const SizedBox(height: _groupSpacing),
                      _MemoryGroup(
                        title: group.title,
                        memories: group.memories,
                        onForget: _inert,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'cactus pro unlocks your full reading memory — tap to upgrade',
              style: context.fonts.interface(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          style: context.fonts.interface(
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
              style: context.fonts.interface(
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
          child: SizedBox(
            height: _noteLineHeight,
            child: Center(
              child: GestureDetector(
                onTap: onForget,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
