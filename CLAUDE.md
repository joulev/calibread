# CLAUDE.md — Project Context for AI Assistants

## What This Project Is

CalibreRead is a native macOS SwiftUI app that reads an existing Calibre ebook library from the filesystem. It is a **read-only** ereader — it never writes to the Calibre library or its `metadata.db`. All user data (reading progress, bookmarks) is stored separately via SwiftData.

The app is for personal use only — not distributed via the App Store. Builds are created by GitHub Actions CI and downloaded directly.

## Build & Run

- **Requires**: macOS 26 (Tahoe), Xcode 26.x
- **Open**: `CalibreRead.xcodeproj` in Xcode, build and run
- **CI**: GitHub Actions builds on every push (`.github/workflows/build.yml`), creates a GitHub Release with a `.zip` on pushes to `main`
- **No code signing**: The app is built unsigned (ad-hoc). After downloading from GitHub, run `xattr -cr CalibreRead.app` once to remove Gatekeeper quarantine

## Architecture

```
CalibreRead/
├── CalibreReadApp.swift              # @main entry point, WindowGroup + Settings scenes
├── Models/
│   ├── CalibreBook.swift             # Book model with authors, tags, series, formats
│   ├── CalibreAuthor.swift           # Author model (id, name, sort, link)
│   ├── CalibreSeries.swift           # Series model (id, name, sort)
│   ├── CalibreTag.swift              # Tag model (id, name)
│   └── ReadingProgress.swift         # SwiftData models: ReadingProgress, BookmarkEntry
├── Services/
│   ├── CalibreDatabase.swift         # SQLite.swift reader for Calibre's metadata.db
│   ├── LibraryManager.swift          # @Observable state manager: books, filtering, sorting
│   └── EPUBService.swift             # EPUBKit parser: chapters, TOC, file URLs
├── Views/
│   ├── ContentView.swift             # Root view: shows WelcomeView or NavigationSplitView
│   ├── Library/
│   │   ├── LibraryView.swift         # Grid/list book browser with search, sort, inspector
│   │   ├── BookGridItem.swift        # Cover thumbnail card for grid view
│   │   ├── BookListRow.swift         # Row with cover + metadata for list view
│   │   ├── SidebarView.swift         # Authors/Series/Tags sidebar navigation
│   │   └── BookDetailView.swift      # Inspector panel: cover, metadata, tags, description
│   ├── Reader/
│   │   ├── ReaderView.swift          # Router: dispatches to EPUB or PDF reader by format
│   │   ├── EPUBReaderView.swift      # EPUB reader with toolbar, chapter nav, progress save
│   │   ├── PDFReaderView.swift       # PDF reader wrapping PDFKit
│   │   └── TableOfContentsView.swift # Chapter list for EPUB TOC
│   └── Settings/
│       └── SettingsView.swift        # Library path configuration
├── Utilities/
│   ├── WebViewRepresentable.swift    # NSViewRepresentable<WKWebView> + ReaderTheme enum
│   └── PDFViewRepresentable.swift    # NSViewRepresentable<PDFView>
└── Resources/
    └── reader.css                    # Default EPUB reading stylesheet
```

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

## Xcode 26 / macOS 26 / Swift 6 Gotchas

These caused real build failures and are worth knowing:

1. **`ForEach` defaults to `Binding` overload**: In SwiftUI macOS 26, `ForEach(collection)` and `ForEach(collection, id:)` prefer the `Binding<C>` overload. Fix: always pass `id:` explicitly, e.g. `ForEach(items, id: \.id)`. If that still fails (nested types confuse type inference), extract the row into a separate `struct` with explicit types, or use `ForEach(0..<count, id: \.self)` with index-based access.

2. **`List(data)` has the same issue**: `List(data, id:) { }` also prefers `Binding`. Fix: use `List { ForEach(data, id:) { } }` instead.

3. **`.accentColor` is not a `ShapeStyle`**: Use `Color.accentColor` instead of `.accentColor` with `.foregroundStyle()`.

4. **EPUBKit 0.5.0 API changes**: `document.spine`, `document.manifest`, `document.tableOfContents` are **non-optional**. `document.contentDirectory` is a `URL`, not a `String`. `item.label` on TOC entries is non-optional.

5. **Swift 6 strict concurrency**: `@objc` methods accessing main-actor-isolated properties need the class marked `@MainActor`.

6. **`#Predicate` needs explicit type**: Use `#Predicate<ReadingProgress> { ... }` not `#Predicate { ... }`. Capture variables in locals before using in predicates.

## App Sandbox

The app sandbox is **disabled** — this is intentional. Sandbox requires a proper Apple signing identity for entitlements to work, and we build unsigned. Without sandbox, the app can freely read the Calibre library folder. The library path is persisted as a plain file path in UserDefaults.

## What's Implemented (v1)

- [x] Open and read any Calibre library folder
- [x] Browse books in grid or list view
- [x] Filter by author, series, or tag via sidebar
- [x] Search across title, author, series, tags
- [x] Sort by title, author, date added, date published
- [x] Book detail inspector with cover, metadata, ratings, tags, HTML description
- [x] EPUB reader with WKWebView rendering
- [x] EPUB themes: light, sepia, dark
- [x] EPUB font size controls (12-32px)
- [x] EPUB chapter navigation + table of contents
- [x] PDF reader with native PDFKit
- [x] Reading progress auto-save/restore (SwiftData)
- [x] Menu bar: Open Library (Cmd+Shift+O), Reload Library (Cmd+R)
- [x] Settings window for library path
- [x] GitHub Actions CI with artifact upload + GitHub Releases

## What's Not Yet Implemented

- [ ] Liquid glass UI (macOS 26 design language) — toolbar and chrome updates needed
- [ ] Bookmarks UI (model exists: `BookmarkEntry`, but no UI to create/view them)
- [ ] "Continue Reading" section on home screen
- [ ] Keyboard shortcuts for reader (arrow keys, space for page down)
- [ ] Multi-window support (open books in separate windows)
- [ ] Full-screen reading mode
- [ ] Annotations and highlights
- [ ] App icon
