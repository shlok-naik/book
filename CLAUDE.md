# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Minimalist AI Book Tracker

Flutter app ("cactus") for tracking reading progress via natural-language commands, with a Supabase backend, Google Books lookup, Groq-powered NL parsing, and RevenueCat purchases.

## Commands

```bash
flutter pub get                          # install dependencies
flutter run                               # run on connected device/emulator
flutter test                              # run all tests
flutter test test/library/library_controller_test.dart   # run a single test file
flutter analyze --fatal-infos --fatal-warnings   # static analysis — must be zero issues
dart format .                             # CI fails on unformatted code
```

CI (`.github/workflows/ci.yml`) runs format, analyze, test, and a Deno
type-check of the edge functions on every push and PR. The analyzer rule
set in `analysis_options.yaml` is deliberately stricter than
`flutter_lints`' default — `unawaited_futures`, `discarded_futures` and
`use_build_context_synchronously` are promoted to errors — so treat a new
hint as a defect, not noise.

### Configuration
Resolved by [lib/core/env/env.dart](lib/core/env/env.dart) — never read `dotenv.env` directly anywhere else. Two sources, in order: compile-time `--dart-define`s, then a local `.env` file. `.env` is ignored outright in release builds (`Env._lookup` returns null under `kReleaseMode`) because it ships as a readable asset — a release missing a define shows `StartupFailureApp` rather than quietly starting on bundled values. Required: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `REVENUECAT_API_KEY`. Optional: `GOOGLE_BOOKS_API_KEY` (missing degrades to keyless search).

**No secret goes in either source** — both reach the device. The Groq API key used to live here and therefore shipped inside every build; it is now a Supabase project secret held by the `parse-command` edge function. If you find yourself adding a key that must stay private, it belongs on the server, not in `Env`.

A build missing a required key renders `StartupFailureApp` naming what is absent, rather than throwing at whichever screen first touches it.

### Database
Schema lives in [supabase/migrations/](supabase/migrations), applied in filename order — **not** a single re-runnable `schema.sql` (the old one truncated `user_books` on every run). Never edit an applied migration; add a new one with `supabase migration new <name>`, then `supabase db push`. Check `supabase db lint` or the dashboard advisors afterwards.

Edge functions live in [supabase/functions/](supabase/functions) and deploy with `supabase functions deploy <name>`; their secrets are set with `supabase secrets set KEY=...`.

## Architecture

### Composition root
There is a single composition root: `_BookAppState` in [lib/main.dart](lib/main.dart). It builds `GoogleBooksApiClient`, `LibraryController` (with its `BookLookupService`, `UserBookRepository`, `ReadingEventRepository`), `SessionService`, and `OnboardingProfileRepository` once, then injects them downward. Every one of these has a nullable constructor-injection seam (`libraryController`, `sessionService`, `profileRepository` on `BookApp`) so tests can substitute fakes without touching Supabase/Google Books/Groq. Never instantiate an HTTP client or repository inside a widget — inject it from here (or thread it down from a caller that got it from here).

### Feature-first layout
Each feature under `lib/features/<name>/` is split into `data/` (repositories/API clients), `domain/` (models, business rules), and `presentation/` (`controllers/`, `pages/`, `widgets/`). `lib/core/` holds cross-feature concerns: `env/`, `supabase/`, `ai/` (Groq client), `purchases/` (RevenueCat), `theme/`, `widgets/`.

- **library** — the reader's shelf. `LibraryController` (a `ChangeNotifier`) is the single mutation point for shelf state; it never talks to Supabase/Google Books directly, only through `BookLookupService` (cache-first: Supabase `books` table → Google Books API → write-back) and `UserBookRepository`. Every command (`start`/`update`/`finish`/`rate`/`delete`) is optimistic: local state updates and notifies immediately, then persists, rolling back on failure. Every successful command also fires-and-forgets a `ReadingEventRepository.log` call for the streaks page — a logging failure never affects the command's own success/failure result.
- **logging** — the natural-language "+"/log page. `LogCommandParser` turns text into the five-command grammar (`start`/`update <page>`/`finish`/`rate <stars>`/`delete <title>`); `AiCommandParser` ([lib/core/ai/ai_command_parser.dart](lib/core/ai/ai_command_parser.dart)) is the "cactus pro" alternative that asks an LLM to split a free-form sentence into that same grammar before handing it to the identical parser — the two entry points converge on one command surface. The real implementation calls the `parse-command` edge function; the model provider's key never reaches the device.
- **streaks** — reads `reading_events` (grouped by local day) to render a GitHub-style dot grid; symbol precedence per day is finish > start > any other action.
- **onboarding** — a linear page sequence ending in `paywall_page.dart` (RevenueCat) → celebration screens. `SessionService` decides whether `RootShell` or `WelcomePage` is the initial route.
- **shell** — `RootShell` hosts the four top-level pages (profile, streaks, library, log) in an `IndexedStack` switched by a floating `BottomSwitcher`; log is the default tab.

### Supabase model
`user_id` columns default to `auth.uid()` at the database level (never set by app code) and RLS is what actually enforces per-reader isolation — anonymous Supabase Auth sessions still get a real `authenticated` role. Every policy calls `(select auth.uid())`, not the bare function, so the planner evaluates it once per query rather than once per row.

- `books` — the shared Google Books cache. Readable by any signed-in reader, **writable by none**: the sole write path is the `cache_book()` security-definer function, because a table-level insert/update grant would also let any reader rewrite or delete rows out from under everyone else.
- `user_books`, `reading_events`, `profiles` — private per reader. `user_books.updated_at` is maintained by the `user_books_touch_updated_at` trigger, never sent from the client (the shelf is ordered by it, so a skewed device clock could otherwise pin its own rows to one end forever).
- `ai_requests` — the AI rate-limit ledger. RLS enabled with *no policies at all*, deliberately: it is reachable only through `claim_ai_request()`, so a reader cannot clear their own history to reset their limit.
- A trigger (`handle_new_user`) creates a blank `profiles` row on first auth, so app code only ever `UPDATE`s it. Its `EXECUTE` grant is revoked from `anon`/`authenticated` — it is a trigger function, not an API.

### Errors, logging and startup
Repositories translate driver failures into exceptions carrying a message already safe to show (`LibraryException`, `OnboardingException`, `AiCommandException`); controllers turn those into result objects. The UI never renders a raw driver error — and never silently swallows one either: a load that failed must look different from a load that came back empty (see `StreaksController.errorMessage`).

All diagnostics go through `AppLogger` ([lib/core/diagnostics/app_logger.dart](lib/core/diagnostics/app_logger.dart)) — never `print`/`debugPrint`, which are compiled out of release builds. For fire-and-forget work use `reportingFailure(...)` rather than `unawaited(x.catchError((_) {}))`, so the failure is recorded instead of dropped. `main` installs `FlutterError.onError`, `PlatformDispatcher.instance.onError` and a guarded zone, so attaching a crash reporter is a matter of setting `AppLogger.sink` once.

### Accessibility and feel
The UI is icon-heavy and text-light, which is precisely the combination that makes an app unusable with VoiceOver/TalkBack unless the labels are deliberate. The tab bar, book tiles and every day on the streak grid carry explicit `Semantics` — a book tile is *one* node reading "Dune by Frank Herbert. Page 150 of 300, 50 percent.", not six fragments ending in five unlabelled star icons. `test/accessibility/semantics_test.dart` pins these down.

Haptics go through `AppHaptics` ([lib/core/feedback/app_haptics.dart](lib/core/feedback/app_haptics.dart)) and have exactly three meanings: `selection()` (you moved), `accepted()` (it worked), `rejected()` (it didn't). Never fire one from a timer, a background event or a screen appearing — only in direct response to a touch the reader just made, and never when the outcome is a no-op (tapping the tab you are already on).

The app is portrait-only, declared in the Android manifest, the iOS plist *and* `SystemChrome` — the streaks page fits a whole year on one screen and has nowhere to put December in landscape. That page scrolls only when it must (large accessibility text sizes), never otherwise.

### Theming
`AppColors` is a `ThemeExtension` (light/dark instances in [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart)) registered on `ThemeData.extensions` in [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart); widgets read colors via `context.colors`, never a hardcoded hex. `ThemeController` (a `ValueListenable<ThemeMode>`) drives the `MaterialApp.themeMode` switch in `main.dart`.

---

## 🎨 Design System: Mono & Teal

### Light Mode
| Role | Color | Hex Code | Usage |
| :--- | :--- | :--- | :--- |
| **Background** | Pure White | `#FFFFFF` | Main app scaffold and empty space. |
| **Surface** | Off-White | `#F5F5F5` | Book cards, bottom navigation, and pop-up sheets. |
| **Primary Text** | Pure Black | `#000000` | Book titles, main reading stats, and AI responses. |
| **Secondary Text** | Gray | `#6B6B6B` | Author names, dates, and placeholder text. |
| **Accent / AI** | Teal | `#1A8FBF` | Progress bars, AI assistant buttons, and active tabs. |
| **Dividers** | Light Gray | `#E8E8E8` | Hairlines, separators, and card borders. |

### Dark Mode
| Role | Color | Hex Code | Usage |
| :--- | :--- | :--- | :--- |
| **Background** | Dark Gray | `#1A1A1A` | Main app scaffold and empty space. |
| **Surface** | Elevated Dark Gray | `#242424` | Book cards, bottom navigation, and pop-up sheets. |
| **Primary Text** | Off-White | `#F5F5F5` | Book titles, main reading stats, and AI responses. |
| **Secondary Text** | Gray | `#9A9A9A` | Author names, dates, and placeholder text. |
| **Accent / AI** | Teal | `#1B9FD9` | Progress bars, AI assistant buttons, and active tabs. |
| **Dividers** | Mid Gray | `#3A3A3A` | Hairlines, separators, and card borders. |

### Typography
*   **Headings/Display**: *Fraunces* – provides a classic, museum-like editorial feel suited for book titles and headers.
*   **Body/UI**: *Inter* – ensures maximum legibility for reading stats, UI labels, and long-form AI summaries.

---

## 🏗️ Production-Ready Modular Code Guidelines

### 1. Feature-First Architecture
Organize the codebase by feature domain rather than technical layers. 
*   **Good**: `features/book_tracking/`, `features/ai_summary/`, `features/library/`
*   **Avoid**: Grouping all models in one folder, all UI components in another.
This isolation ensures that changes to the AI feature don't accidentally break the core book tracking logic.

### 2. Separation of Concerns (Dumb UI)
Keep your UI components strictly focused on presentation. Extract all business logic, API calls, and data transformations into dedicated state management controllers or view-models. The UI should only listen to state changes and dispatch user actions.

### 3. Dependency Injection
Never instantiate HTTP clients or AI service classes directly inside your UI or business logic. Inject them. This makes it trivial to swap out a real AI backend for a mocked version during testing or development, avoiding unnecessary API costs.

### 4. Theme Extensions
Do not hardcode the hex values from the design system directly into UI components. Define the Light and Dark schemes centrally using theme extensions. This ensures that toggling between the Light and Dark modes updates the entire app consistently and instantly.

---

## 🧪 Testing Strategy

### Unit Tests
*   **Focus**: Business logic, data parsing, and AI prompt generation.
*   **Action**: Ensure that your data models accurately serialize and deserialize the AI's responses (especially if parsing JSON from an LLM). Test edge cases, such as network timeouts or malformed AI output, to ensure the app degrades gracefully rather than crashing.

### Component / UI Tests
*   **Focus**: Reusable UI elements (e.g., the Teal progress ring, book cover cards, AI summary bottom sheets).
*   **Action**: Render these components in isolation. Verify that the progress bar accurately reflects 0%, 50%, and 100% states. Ensure the text contrast remains readable in both Light and Dark themes.

### Integration Tests
*   **Focus**: Core user journeys.
*   **Action**: Write end-to-end tests for the primary flows:
    1. Adding a new book to the library.
    2. Logging reading progress.
    3. Tapping the "Ask AI" button and displaying the result.
*   **Mocking**: Use mocking libraries (like `mocktail` or `mockito` in Dart/Flutter) to intercept the AI network requests during integration tests. This keeps the test suite fast, deterministic, and free from external API dependencies.
