# cactus

**A reading tracker you talk to.** Type what you did — `started dune`,
`on page 240`, `finished it, four and a half stars` — and cactus files it:
the shelf, the progress, the streak, the stats. No forms, no screens to
tap through.

Built for the **RevenueCat Shipathon 2026 — Next Gen track**.

Flutter · Supabase (Postgres, Auth, Edge Functions) · RevenueCat ·
Google Books + Open Library.

---

## What it does

- **Log by typing.** A classic command grammar (`start`, `update`,
  `finish`, `rate`, `move`, `make shelf|tag|series`, `add tag|series|comment`,
  `remove`, `delete`) for everyone, plus a free on-device **beta parser**
  that understands everyday sentences, forgives typos and matches titles
  against your shelf. On *cactus pro*, an LLM splits whole rambling
  messages ("finished dune, loved it, and started circe yesterday") into
  those same commands.
- **Shelves as folders.** Currently reading up top, custom shelves, drag
  a book to reorder, move it, or drop it in the bin. Series, tags,
  comments, owned editions, re-read stickers.
- **Search and discover.** Google Books with an automatic Open Library
  fallback, plus recommendation rows built from your shelf and tastes —
  no AI needed.
- **Stats.** Yearly goal, reading-days heatmap, pace, genres, tags.
- **Offline first.** Shelf changes queue on the device and sync in order
  when the connection returns.
- **Yours.** Anonymous account from the first launch (no sign-up wall),
  optional verified email link to secure the library across devices,
  Goodreads import and CSV export.
- **Customisation.** Accent themes, font sets and sixteen launcher icons.

## How RevenueCat is used

cactus is free at its core and sells **cactus pro**, a subscription with a
monthly and a yearly plan.

- `PurchasesService` wraps the RevenueCat SDK; the reader is identified by
  their Supabase user id so the entitlement survives an email link.
- `PlanController.isPro` follows the live entitlement (`customerInfoStream`),
  and every gate reads it: natural-language AI, memory and recommendations,
  the pro stats, collection limits on the free plan, themes/fonts/icons and
  the Goodreads import. Every check **fails closed**.
- The paywall (`showPaywallPopup`) is always dismissible, opens on the
  chapter matching the feature that was tapped (`PaywallFeature`), and shows
  the store's own localized prices.
- RevenueCat's Customer Center and restore are in settings.
- Purchase outcomes (cancelled / store error / entitlement inactive) are
  tracked separately; no reader-authored content is ever sent.

## Architecture at a glance

One composition root (`lib/main.dart`), feature-first folders, controllers
as the single mutation point, optimistic updates with rollback, Supabase RLS
for per-reader isolation, secrets only on the server (the LLM and Google
Books keys live in edge functions). Full guide: [CLAUDE.md](CLAUDE.md).

---

# Developer guide

## Getting started

```bash
flutter pub get
cp .env.example .env   # then fill it in — see Configuration
flutter run
```

### Everyday commands

```bash
flutter analyze --fatal-infos --fatal-warnings   # must be zero issues
flutter test                                     # whole suite
flutter test test/library/library_controller_test.dart   # one file
dart format .                                    # CI checks this
```

---

## Configuration

Configuration resolves in two steps, in order (see
[`lib/core/env/env.dart`](lib/core/env/env.dart) — nothing else in the app
reads `dotenv` directly):

1. **`--dart-define`**, compiled into the binary. This is how release
   builds should be configured.
2. **`.env`**, for local development — and only in debug and profile
   builds. It is git-ignored but *is* bundled as a Flutter asset, so
   anything in it is readable by anyone who unzips a build; a release
   build therefore refuses to read it at all, and one missing a
   `--dart-define` shows the configuration screen instead of quietly
   starting on bundled values.

| Key | Required | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | yes | |
| `SUPABASE_ANON_KEY` | yes | Publishable key. Public by design — RLS is what gates the data. |
| `REVENUECAT_API_KEY` | yes | RevenueCat's *public* SDK key, not a secret API key. |
| `GOOGLE_BOOKS_API_KEY` | no | Without it, search falls back to Google Books' lower-quota anonymous access. |

A build missing a required key shows a configuration screen naming what
is absent, rather than throwing at whichever screen first happens to need
it.

**No secret belongs in either source** — both reach the device. The model
provider's API key is deliberately not among them; it is a Supabase
project secret (see below).

Release build (`appbundle` is what Play takes; `apk` is for sideloading):

```bash
flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=REVENUECAT_API_KEY=... --dart-define=GOOGLE_BOOKS_API_KEY=...
```

### Release signing (Android)

Release builds are signed from `android/key.properties`, which is
git-ignored — copy `android/key.properties.example` and fill it in. Without
it the build still succeeds but falls back to the **debug** key and prints a
warning; Play will not accept an upload signed that way. Generate the
keystore once and keep it safe — Play will not accept a future update signed
with a different key:

```bash
keytool -genkey -v -keystore ~/cactus-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Release builds run R8 (`isMinifyEnabled` + `isShrinkResources`); keep rules
live in `android/app/proguard-rules.pro`.

---

## Supabase

### Migrations

Schema changes are migration files under
[`supabase/migrations/`](supabase/migrations), applied in filename order.
There is no `schema.sql` any more — a single re-runnable script cannot
express a change that is *not* idempotent, and the old one truncated
`user_books` every time it ran.

```bash
supabase link --project-ref <ref>
supabase db push          # apply pending migrations
supabase migration new <name>   # start a new one
```

Never edit an applied migration; add another.

### Edge functions

[`parse-command`](supabase/functions/parse-command/index.ts) turns a
free-form sentence into command lines. It exists so the model provider's
API key stays on the server:

```bash
supabase secrets set GROQ_API_KEY=...
supabase functions deploy parse-command
```

The [`google-books`](supabase/functions/google-books/index.ts) proxy keeps the
Google Books key server-side, and `link-account` merges a device library into
an email account. All three need a valid JWT.

`parse-command` charges each call against the caller's own
hourly allowance (`claim_ai_request()`), so an extracted request is worth
no more than that reader's remaining quota.

### Data model

| Table | Ownership |
| --- | --- |
| `books`, `book_editions` | Shared catalogue cache. Readable by any signed-in reader; **not** writable — only the `cache_book*()` security-definer functions write. |
| `user_books` | One row per book per reader: status, progress, rating, shelf, series, owned edition. Private via RLS. |
| `shelves`, `tags`, `series`, `book_tags`, `book_comments` | The reader's own collections and notes. Private via RLS. |
| `reading_events` | One row per shelf command that took effect; feeds the heatmap and streak. Private via RLS. |
| `profiles`, `memories` | Name, goal, saved notes. Private via RLS. |
| `ai_requests` | The AI rate-limit ledger. RLS on with **no policies at all** — reachable only through `claim_ai_request()`. |

`user_id` columns default to `auth.uid()` at the database level and are
never set by app code; RLS is what actually enforces per-reader
isolation. Anonymous Supabase Auth sessions still carry the
`authenticated` role, so they are covered by the same policies.

Run `supabase db lint`, or the advisors in the dashboard, after any schema
change.

---

## Architecture

See [CLAUDE.md](CLAUDE.md) for the full guide. In short:

- **One composition root.** `_BookAppState` in
  [`lib/main.dart`](lib/main.dart) builds every client and repository once
  and injects them downward. No widget constructs its own HTTP client.
- **Feature-first.** `lib/features/<name>/` splits into `data/`,
  `domain/`, `presentation/`. `lib/core/` holds cross-feature concerns.
- **Optimistic commands.** Every shelf command updates local state and
  notifies immediately, then persists, rolling back on failure.
- **Errors are values at the UI boundary.** Repositories translate driver
  errors into exceptions carrying a message that is already safe to show;
  controllers turn those into result objects. The UI never renders a raw
  driver error, and never silently swallows one.
- **Accessibility is part of the widget, not a later pass.** The UI is
  icon-heavy and text-light, which is exactly what breaks a screen reader
  — so the tab bar, the book tiles and every day on the streak grid carry
  deliberate labels, covered by `test/accessibility/semantics_test.dart`.
- **Haptics have a fixed vocabulary** (`AppHaptics`): one pattern for
  "you moved", one for "that worked", one for "that didn't", and nothing
  else gets one.
- **Logging goes through `AppLogger`**
  ([`lib/core/diagnostics/app_logger.dart`](lib/core/diagnostics/app_logger.dart)),
  not `print`/`debugPrint` — it survives release builds, and
  [`CrashReporter`](lib/core/diagnostics/crash_reporter.dart) attaches
  Crashlytics to it in one place rather than at every call site.

---

## Crash reporting

Firebase Crashlytics, attached at `AppLogger.sink` — see
[`lib/core/diagnostics/crash_reporter.dart`](lib/core/diagnostics/crash_reporter.dart).
Warnings report as non-fatal, errors as fatal (that is what feeds
crash-free-users); debug and info never leave the device.

**Do not follow Firebase's own Flutter setup guide for the error
handlers.** It tells you to assign
`FirebaseCrashlytics.instance.recordFlutterFatalError` to
`FlutterError.onError`. [`main.dart`](lib/main.dart) already owns that
handler, `PlatformDispatcher.onError` and the guarded zone, and forwards
all three into `AppLogger` — adding Firebase's on top double-reports
every framework error.

Collection is off in debug builds. To verify the pipeline end to end,
temporarily flip the `setCrashlyticsCollectionEnabled` call and force a
crash.

R8 obfuscates release builds, and the Crashlytics Gradle plugin uploads
the mapping file automatically so Android traces stay readable. **Don't
add `--obfuscate`** to the Flutter build: Crashlytics cannot symbolize
obfuscated *Dart* traces, which would need `--split-debug-info` and
`flutter symbolize` by hand.

Crashlytics collects device identifiers, so it has to be declared in App
Store Connect's privacy questions and Play's Data Safety form.

---

## Analytics

Firebase Analytics, in
[`lib/core/analytics/app_analytics.dart`](lib/core/analytics/app_analytics.dart).
It exists to answer one question: **where in onboarding do people stop.**
Eight screens run before anyone sees a price, and without this a reader
who quit at the reading-goal question looks identical to one who never
opened the app.

Screen views come from each route's `RouteSettings` name via a navigator
observer — not from a line in every page's `initState`. **When you add an
onboarding screen, give its `MaterialPageRoute` a `settings:` name**, or it
silently vanishes from the funnel. Paywall and purchase events are explicit
calls, because "saw an offer" and "acted on it" are the two numbers worth
being exact about; `paywall_viewed` fires only once real prices render, so
a reader who hit the "couldn't load pricing" state is not counted as having
seen one.

**Nothing the reader wrote is ever sent** — no book titles, authors, typed
commands, profile answers, or email. Every parameter is a screen name or an
enum-like constant. If a value came from a text field, it does not go here.
Events are tied to the same opaque Supabase UUID that tags crash reports.

---

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push
and pull request: `dart format --set-exit-if-changed`, `flutter analyze
--fatal-infos --fatal-warnings`, `flutter test --coverage`, and a Deno
type-check of the edge functions.
