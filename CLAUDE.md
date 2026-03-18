# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Calibread is a native macOS SwiftUI app that reads an existing Calibre ebook library from the filesystem. It is a **read-only** ereader — it never writes to the Calibre library or its `metadata.db`. All user data (reading progress, bookmarks) is stored separately via SwiftData.

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
  Built app output: `build/Build/Products/Release/Calibread.app`
- **CI**: GitHub Actions (`.github/workflows/build.yml`) builds on pushes to `main`, uploads a `.zip` artifact
- **No code signing**: Built unsigned (ad-hoc). After downloading, run `xattr -cr Calibread.app` to remove Gatekeeper quarantine
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
EPUBReaderView (state: fraction, CFI, theme, font size)
  → FoliateWebView (NSViewRepresentable<WKWebView>)
    → EPUBSchemeHandler (WKURLSchemeHandler, serves book + app resources via calibre:// scheme)
    → bridge.js (Swift ↔ foliate-js communication layer)
      → <foliate-view> (foliate-js custom element, handles EPUB parsing, pagination, rendering)
        - CSS column layout via paginator.js (iframes + blob URLs per section)
        - Native vertical-rl, RTL, and CJK support
        - EPUB CFI-based position tracking
        - Bisection-based visible range detection
    → FoliatePageController (direct JS calls for navigation)
```

**Key design decisions:**
- Uses [foliate-js](https://github.com/johnfactotum/foliate-js) (vendored, MIT) for all EPUB rendering
- `FoliatePageController` provides direct WKWebView JS access so arrow keys don't queue through `updateNSView`
- Single WKWebView per book — foliate-js manages chapter transitions internally via iframes
- Reading position is stored as both EPUB CFI (precise) and 0–1 fraction (fallback)
- EPUB parsing happens in JavaScript (foliate-js `epub.js`), not Swift — EPUBKit dependency removed
- `EPUBSchemeHandler` serves the EPUB file via `calibre://book` and app resources via `calibre://app/`

### Window Management

`BookWindowData` is a lightweight `Codable` struct passed to `openWindow(value:)` for reader windows. `CalibreReadApp.swift` defines two `WindowGroup`s: the main library window and per-book reader windows.

### Key Source Locations

| Area | Key Files |
|------|-----------|
| Data layer | `Services/CalibreDatabase.swift`, `Services/LibraryManager.swift` |
| Models | `Models/CalibreBook.swift`, `Models/ReadingProgress.swift`, `Models/BookWindowData.swift` |
| EPUB reading | `Views/Reader/EPUBReaderView.swift`, `Utilities/FoliateWebView.swift`, `Utilities/EPUBSchemeHandler.swift` |
| EPUB JS engine | `Resources/foliate/` (vendored foliate-js), `Resources/bridge.js`, `Resources/reader.html` |
| PDF reading | `Views/Reader/PDFReaderView.swift`, `Utilities/PDFViewRepresentable.swift` |
| Library UI | `Views/Library/LibraryView.swift`, `Views/Library/SidebarView.swift` |
| Reader themes | `Utilities/ReaderTheme.swift` |
| Settings | `Views/Settings/SettingsView.swift` |

## Key Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | 0.15.3+ | Read-only access to Calibre's `metadata.db` |
| [foliate-js](https://github.com/johnfactotum/foliate-js) | vendored (MIT) | EPUB rendering, parsing, pagination (JS, bundled in Resources) |

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

4. **Swift 6 strict concurrency**: `@objc` methods accessing main-actor-isolated properties need the class marked `@MainActor`.

5. **`#Predicate` needs explicit type**: Use `#Predicate<ReadingProgress> { ... }` not `#Predicate { ... }`. Capture variables in locals before using in predicates.

## What's Not Yet Implemented

- [ ] Liquid glass UI (macOS 26 design language) — toolbar and chrome updates needed
- [ ] Bookmarks UI (model exists: `BookmarkEntry`, but no UI to create/view them)
- [ ] "Continue Reading" section on home screen
- [ ] Multi-window support (open books in separate windows)
- [ ] Full-screen reading mode
- [ ] Annotations and highlights (foliate-js overlay system available but not wired to UI)
- [ ] In-book search (foliate-js search API available but not wired to UI)
