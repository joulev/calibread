# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

CalibreRead is a native macOS SwiftUI app that reads an existing Calibre ebook library from the filesystem. It is a **read-only** ereader — it never writes to the Calibre library or its `metadata.db`. All user data (reading progress, bookmarks) is stored separately via SwiftData.

The app is for personal use only — not distributed via the App Store. Builds are created by GitHub Actions CI and downloaded directly.

## Build & Run

- **Requires**: macOS 26 (Tahoe), Xcode 26.x
- **Open**: `CalibreRead.xcodeproj` in Xcode, build and run (Cmd+R)
- **CLI build**:
  ```bash
  xcodebuild build \
    -project CalibreRead.xcodeproj \
    -scheme CalibreRead \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM=""
  ```
  Built app output: `build/Build/Products/Release/CalibreRead.app`
- **CI**: GitHub Actions (`.github/workflows/build.yml`) builds on every push, creates a GitHub Release with a `.zip` on pushes to `main`
- **No code signing**: Built unsigned (ad-hoc). After downloading, run `xattr -cr CalibreRead.app` to remove Gatekeeper quarantine
- **No tests or linting**: The project has no test targets, no SwiftLint, and no test steps in CI. The CI build succeeding is the only automated check.

## Architecture

This is a native Xcode project (`CalibreRead.xcodeproj`), not a Swift Package. SPM dependencies are configured in the Xcode project file.

### Data Flow

```
CalibreDatabase (SQLite.swift, read-only)
  → LibraryManager (@Observable, single source of truth for all book data)
    → Views (ContentView → SidebarView + LibraryView + BookDetailView)
```

All books are loaded once when the library is opened. Filtering (by author/series/tag/search) and sorting happen as computed properties on `LibraryManager`.

### EPUB Reader Pipeline

```
EPUBReaderView (state: chapter index, page, theme, font size)
  → EPUBService (parses EPUB: tries EPUBKit, falls back to manual OPF parser)
    → EPUBWebView (NSViewRepresentable<WKWebView>)
      ↔ JavaScript "CalibreReader" global (bidirectional via WKScriptMessageHandler)
        - CSS column layout for pagination
        - nextPage()/prevPage() via translateX transforms
        - Reports {current, total} page changes to Swift
    → EPUBPageController (direct JS calls, used by keyboard handlers)
    → EPUBPaginator (measures all chapters in parallel via hidden WKWebView pool)
      → PaginationCache (JSON files in /tmp, 7-day TTL, keyed by viewport+font+theme)
```

**Key design decisions:**
- `EPUBPageController` provides direct WKWebView JS access so arrow keys don't queue through `updateNSView`
- Reading position is stored as a 0–1 fraction (robust to font/theme reflow changes)
- `EPUBPaginator` uses 4 hidden WKWebViews in invisible windows, processing chapters in batches — start all loads simultaneously, then collect results

### Window Management

`BookWindowData` is a lightweight `Codable` struct passed to `openWindow(value:)` for reader windows. `CalibreReadApp.swift` defines two `WindowGroup`s: the main library window and per-book reader windows.

### Key Source Locations

| Area | Key Files |
|------|-----------|
| Data layer | `Services/CalibreDatabase.swift`, `Services/LibraryManager.swift` |
| Models | `Models/CalibreBook.swift`, `Models/ReadingProgress.swift`, `Models/BookWindowData.swift` |
| EPUB reading | `Services/EPUBService.swift`, `Views/Reader/EPUBReaderView.swift`, `Utilities/WebViewRepresentable.swift` |
| EPUB pagination | `Services/EPUBPaginator.swift` (parallel measurement + disk cache) |
| PDF reading | `Views/Reader/PDFReaderView.swift`, `Utilities/PDFViewRepresentable.swift` |
| Library UI | `Views/Library/LibraryView.swift`, `Views/Library/SidebarView.swift` |
| Reader themes/CSS | `ReaderTheme` enum in `WebViewRepresentable.swift`, `Resources/reader.css` |

## Key Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | 0.15.3+ | Read-only access to Calibre's `metadata.db` |
| [EPUBKit](https://github.com/witekbobrowski/EPUBKit) | 0.5.0+ | EPUB parsing (requires Swift tools 6.0) |

## How the Calibre Integration Works

Calibre stores its library as:
```
Library Root/
├── metadata.db                    # SQLite — the source of truth
├── Author Name/
│   └── Book Title (123)/
│       ├── cover.jpg
│       ├── metadata.opf
│       └── Book Title - Author.epub
```

`CalibreDatabase.swift` reads `metadata.db` with SQLite.swift. Key tables:
- `books` — core book metadata (title, path, dates, has_cover, uuid)
- `authors`, `tags`, `series`, `publishers`, `ratings`, `languages` — entity tables
- `books_authors_link`, `books_tags_link`, etc. — many-to-many junction tables
- `data` — tracks ebook format files (format, filename, size) per book
- `comments` — HTML book descriptions

The `books.path` column gives the relative path to each book's folder from the library root. Cover images are at `{path}/cover.jpg`. Format files are at `{path}/{data.name}.{format.lowercased()}`.

## App Sandbox

The app sandbox is **disabled** — this is intentional. Sandbox requires a proper Apple signing identity for entitlements to work, and we build unsigned. Without sandbox, the app can freely read the Calibre library folder. The library path is persisted as a plain file path in UserDefaults.

## Xcode 26 / macOS 26 / Swift 6 Gotchas

These caused real build failures and are worth knowing:

1. **`ForEach` defaults to `Binding` overload**: In SwiftUI macOS 26, `ForEach(collection)` and `ForEach(collection, id:)` prefer the `Binding<C>` overload. Fix: always pass `id:` explicitly, e.g. `ForEach(items, id: \.id)`. If that still fails (nested types confuse type inference), extract the row into a separate `struct` with explicit types, or use `ForEach(0..<count, id: \.self)` with index-based access.

2. **`List(data)` has the same issue**: `List(data, id:) { }` also prefers `Binding`. Fix: use `List { ForEach(data, id:) { } }` instead.

3. **`.accentColor` is not a `ShapeStyle`**: Use `Color.accentColor` instead of `.accentColor` with `.foregroundStyle()`.

4. **EPUBKit 0.5.0 API changes**: `document.spine`, `document.manifest`, `document.tableOfContents` are **non-optional**. `document.contentDirectory` is a `URL`, not a `String`. `item.label` on TOC entries is non-optional.

5. **Swift 6 strict concurrency**: `@objc` methods accessing main-actor-isolated properties need the class marked `@MainActor`.

6. **`#Predicate` needs explicit type**: Use `#Predicate<ReadingProgress> { ... }` not `#Predicate { ... }`. Capture variables in locals before using in predicates.

7. **`withTaskGroup` + `@MainActor` closures**: `group.addTask { @MainActor in ... }` is rejected by Swift 6's region-based isolation checker. Instead of TaskGroup with @MainActor closures, use a batched approach: start all work items (non-blocking), then await results sequentially. For WKWebView pools, split into `startLoad()` (fire-and-forget) + `awaitMeasurement()` (suspend until done).

## What's Not Yet Implemented

- [ ] Liquid glass UI (macOS 26 design language) — toolbar and chrome updates needed
- [ ] Bookmarks UI (model exists: `BookmarkEntry`, but no UI to create/view them)
- [ ] "Continue Reading" section on home screen
- [ ] Keyboard shortcuts for reader (arrow keys, space for page down)
- [ ] Multi-window support (open books in separate windows)
- [ ] Full-screen reading mode
- [ ] Annotations and highlights
- [ ] App icon
