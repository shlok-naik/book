# cactus

A minimalist reading tracker. You log your reading by typing what you did
— `start Dune`, `update Dune 240`, `finish Dune`, `rate Dune 4.5` — and on
*cactus pro*, by typing it as a plain sentence and letting a model split
it into those same commands.

Flutter app, Supabase backend (Postgres + Auth + Edge Functions), Google
Books for volume lookup, RevenueCat for purchases.

---

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

It requires a valid JWT, and charges each call against the caller's own
hourly allowance (`claim_ai_request()`), so an extracted request is worth
no more than that reader's remaining quota.

### Data model

| Table | Ownership |
| --- | --- |
| `books` | Shared cache of Google Books volumes. Readable by any signed-in reader; **not** writable — the one write path is the `cache_book()` function. |
| `user_books` | One row per book per reader. Private via RLS. |
| `reading_events` | One row per shelf command that took effect; the streaks grid groups these by local day. Private via RLS. |
| `profiles` | Onboarding answers. Created by trigger on sign-up, so the app only ever `UPDATE`s. Private via RLS. |
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

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push
and pull request: `dart format --set-exit-if-changed`, `flutter analyze
--fatal-infos --fatal-warnings`, `flutter test --coverage`, and a Deno
type-check of the edge functions.
