# Minimalist AI Book Tracker

## 🎨 Design System: Parchment & Cobalt

### Light Mode
| Role | Color | Hex Code | Usage |
| :--- | :--- | :--- | :--- |
| **Background** | Warm Paper | `#F9F9F6` | Main app scaffold and empty space. |
| **Surface** | Pure White | `#FFFFFF` | Book cards, bottom navigation, and pop-up sheets. |
| **Primary Text** | Soft Black | `#1A1C20` | Book titles, main reading stats, and AI responses. |
| **Secondary Text** | Ash Gray | `#6E737D` | Author names, dates, and placeholder text. |
| **Accent / AI** | Vibrant Cobalt | `#2E5EFF` | Progress bars, AI assistant buttons, and active tabs. |

### Dark Mode
| Role | Color | Hex Code | Usage |
| :--- | :--- | :--- | :--- |
| **Background** | Deep Navy | `#16233E` | Main app scaffold and empty space. |
| **Surface** | Elevated Navy | `#1E2B49` | Book cards, bottom navigation, and pop-up sheets. |
| **Primary Text** | Off-White | `#F9F9F6` | Book titles, main reading stats, and AI responses. |
| **Secondary Text** | Slate | `#8B94A3` | Author names, dates, and placeholder text. |
| **Accent / AI** | Vibrant Cobalt | `#2E5EFF` | Progress bars, AI assistant buttons, and active tabs. |

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
Do not hardcode the hex values from the design system directly into UI components. Define the Light and Dark schemes centrally using theme extensions. This ensures that toggling between the Parchment and Navy modes updates the entire app consistently and instantly.

---

## 🧪 Testing Strategy

### Unit Tests
*   **Focus**: Business logic, data parsing, and AI prompt generation.
*   **Action**: Ensure that your data models accurately serialize and deserialize the AI's responses (especially if parsing JSON from an LLM). Test edge cases, such as network timeouts or malformed AI output, to ensure the app degrades gracefully rather than crashing.

### Component / UI Tests
*   **Focus**: Reusable UI elements (e.g., the Cobalt progress ring, book cover cards, AI summary bottom sheets).
*   **Action**: Render these components in isolation. Verify that the progress bar accurately reflects 0%, 50%, and 100% states. Ensure the text contrast remains readable in both Light and Dark themes.

### Integration Tests
*   **Focus**: Core user journeys.
*   **Action**: Write end-to-end tests for the primary flows:
    1. Adding a new book to the library.
    2. Logging reading progress.
    3. Tapping the "Ask AI" button and displaying the result.
*   **Mocking**: Use mocking libraries (like `mocktail` or `mockito` in Dart/Flutter) to intercept the AI network requests during integration tests. This keeps the test suite fast, deterministic, and free from external API dependencies.
