# Code review — 2026-09-15

An automated review of `main` (295 files), saved for later. **Not fixed yet**,
except where a status note says otherwise. 16 findings: 2 critical, 7 major, 7 minor.

Status notes were added when the file was saved (at commit `59f805f`):

- **Fixed** — already addressed in an earlier commit.
- **Check** — the finding says the code doesn't compile, but
  `flutter analyze --fatal-infos --fatal-warnings` passes on `main`. Confirm
  before changing anything.
- No note — still open.

---

## Critical

### 1. `reading_stats.dart:136-137` — pass a non-nullable `DateTime` to `isAfter`
*Functional correctness* · **Check:** analyzer passes. Dart 3 promotes
`importLocal` through the `baselineThisYear` local boolean, so this compiles
today. Inlining the condition would still make the code clearer.

`importLocal` is `DateTime?` (line 98). The review says it isn't promoted
through the separate `baselineThisYear` boolean, so `finishedAt!.isAfter(importLocal)`
would not compile. It suggests capturing the non-null value once, either with
`if (importLocal != null && importLocal.year == year)` or with `importLocal!`.

### 2. `paywall_page.dart:845` — convert the clamped chapter to `int`
*Functional correctness* · **Check:** analyzer passes. `int.clamp(int, int)`
is statically typed `int` in Dart 3.

The review says `clamp` returns `num`, but `_page` and
`PageController.initialPage` need `int`. Proposed fix:
`widget.initialChapter.clamp(0, _chapters.length - 1).toInt()`.

---

## Major

### 3. `onboarding/presentation/pages/goodreads_prompt_page.dart:46` (also 56, 72) — use the app font theme
*Maintainability*

The page calls `GoogleFonts.ebGaramond` and `GoogleFonts.inter` directly. That
ignores the reader's font theme and uses the runtime font loader instead of the
bundled assets. Switch to `context.fonts.bookTitle(...)` / `context.fonts.body(...)`.

Note: CLAUDE.md says onboarding *deliberately* keeps fixed faces, so decide
whether this page should follow the reader's font theme. Either way, the fixed
faces must come from the bundled assets.

### 4. `CLAUDE.md:68` — resolve the custom-shelf entitlement rule
*Functional correctness*

One section says shelves are available on the free plan. Another (the onboarding
section) says `make shelf` is Pro because custom shelves are Pro. State one rule
for built-in and custom shelves, then apply it in the code and tests.

### 5. `supabase/migrations/20260920000000_import_baseline.sql:12-14` — make library replacement and baseline marking atomic
*Data integrity* · **Fixed** in `df0ffbb`: `20260921000000_atomic_import_baseline.sql`
(applied as remote `atomic_import_baseline`). `replace_library` now marks the
rows and stamps the profile, and `mark_library_imported()` is dropped.

### 6. `supabase/functions/parse-command/index.ts:69` — add `restart` to the command grammar
*Functional correctness*

The reread migration added `restart <book> [date]`, but the prompt says only
the listed commands exist and doesn't list it. Natural-language reread requests
can't produce it. Add `restart <book title> [date]` after `finish` in the prompt,
explain what it does, then redeploy `parse-command`. (The `remove` grammar
and the add-to-library rule are also still waiting on a redeploy.)

### 7. `paywall/presentation/pro_gate.dart:32-33` — inject `PurchasesService` from the composition root
*Maintainability*

`ProGateState` constructs the production purchases client inside widget state.
Have the owning widget or a scope provide the configured instance instead.

### 8. `library_transfer/presentation/controllers/import_controller.dart:192` — don't hardcode Pro entitlement
*Security & privacy*

`isPro: true` lets `ImportController.confirm()` skip the free series cap without
checking the current entitlement. A non-Pro caller, or a reader whose entitlement
changes after opening the page, can create unlimited series. Inject the current
entitlement, fail closed, and pass the relevant `PaywallFeature` through the
locked entry point.

### 9. `core/offline/pending_write_queue.dart:60-72` — a write queued while the same row is replaying is lost
*Data integrity*

`enqueue` merges a new `PendingUpdate` into `_writes.last` and keeps the older
entry's id. `SyncCoordinator._drain` sends a snapshot entry, awaits it, then
calls `queue.remove(write.id)`.

1. The drain sends the queued update for row `r`.
2. While that request is in flight, the reader changes `r` again. It gets queued
   and merged into the in-flight entry under the same id.
3. The request succeeds and the drain removes that id, merged columns included.
   Those columns were never sent. `onSynced` reloads from the server, so the
   second change disappears.

Proposed fix: add an `inFlightId` to the queue. Never merge into that entry.
`_drain` sets it before `executor.execute(write)` and clears it after each outcome.

---

## Minor

### 10. `CLAUDE.md:98` — remove the obsolete journal claim
The offline mode section says "the shelf and journal keep working", but the
journal was removed. Only `reading_events` remain, for the heatmap and the streak.
Name what actually works offline.

### 11. `test/streaks/stats_page_test.dart:586-593` — use an on-shelf tag to test the PRO gate
The fixture has `BookTag(userBookId: 'u1')` but no shelf books, and
`ReadingStats.tagCounts` ignores tags whose book isn't on the shelf. So the
assertion would pass even if the free-plan view leaked real tags. Add a matching
`LibraryBook` and keep both assertions: the real tag is hidden, the invented
preview tag shows.

### 12. `library/presentation/controllers/book_detail_controller.dart:365-367` — deduplicate by id, not object equality
`_reinserted` uses `current.contains(item)`. `BookTag` and `BookComment` have no
value equality, so a refresh during an in-flight removal leaves a different
instance with the same id, and the rollback adds a duplicate. Compare ids instead:
add an `idOf` parameter and pass `(t) => t.id` / `(c) => c.id`.

### 13. `goals/domain/reading_goal.dart:72` (also 76-78) — cap the baseline expectation at the goal
If `base.books > goal`, `expectedBy` returns more books than the goal (e.g. after
the goal is lowered). Use `baselineBooks = min(base.books, goal)` in every
baseline calculation, and return `goal` when nothing remains.

### 14. `onboarding/presentation/widgets/tier_label.dart:48` (also 70) — use the app font service
Both widgets call `GoogleFonts.jetBrainsMono` directly, which ignores the font set
chosen on the customisation page. Use `context.fonts.interface(...)`, subject to
the same onboarding caveat as #3.

### 15. `library/presentation/widgets/series_selection_sheet.dart:69` — reject malformed series positions before writing
`double.tryParse(raw)` turns invalid non-empty input into `null`, which the write
treats as a blank position. Block the write and show a validation message.

### 16. `streaks/domain/reading_stats.dart:54-90` — use a fresh shelf list in each test case
`ReadingStats.forShelf` returns `last.stats` when the list is the same object,
`importedAt` matches and the year hasn't changed. A test that mutates and reuses
one list can get stale stats from the previous case.
