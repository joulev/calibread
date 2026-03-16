# CalibreRead — macOS Ereader for Calibre Libraries

## Overview

A fully native, SwiftUI macOS application that reads an existing Calibre library from the filesystem and provides a beautiful reading experience for EPUB and PDF books. The app is read-only — it does not modify the Calibre library.

---

## Architecture

### Tech Stack
- **Language**: Swift 6
- **UI Framework**: SwiftUI (macOS 14+ / Sonoma)
- **EPUB Parsing**: EPUBKit (lightweight MIT-licensed parser via SPM)
- **EPUB Rendering**: WKWebView wrapped in `NSViewRepresentable`
- **PDF Rendering**: PDFKit (`PDFView` wrapped in `NSViewRepresentable`)
- **Calibre DB Access**: SQLite.swift (read-only access to `metadata.db`)
- **App Data Persistence**: SwiftData (reading progress, bookmarks, app preferences)
- **Package Manager**: Swift Package Manager

### Why These Choices
- **EPUBKit over Readium**: Readium is comprehensive but heavy. Since we only need parsing (not DRM, OPDS, audiobooks), EPUBKit is simpler and gives us full control over the rendering layer.
- **SQLite.swift for Calibre DB**: We need read-only access to `metadata.db`. A lightweight SQLite wrapper is ideal — no need for Core Data or SwiftData for this since the schema is externally defined.
- **SwiftData for app state**: Reading positions, bookmarks, and user preferences are our own data — SwiftData is the modern, SwiftUI-native choice.

---

## Calibre Library Structure (Reference)

```
Calibre Library/
├── metadata.db                          # SQLite database
├── Author Name/
│   └── Book Title (123)/
│       ├── cover.jpg                    # Cover image
│       ├── metadata.opf                 # Metadata backup (XML)
│       └── Book Title - Author Name.epub
```

### Key Database Tables
- **`books`**: id, title, sort, author_sort, timestamp, pubdate, series_index, path, has_cover
- **`authors`** / **`books_authors_link`**: Author names with many-to-many link
- **`tags`** / **`books_tags_link`**: Genre/category tags
- **`series`** / **`books_series_link`**: Series with position (series_index)
- **`data`**: Format files — book id, format (EPUB/PDF/etc), filename, size
- **`comments`**: Book descriptions (HTML)
- **`ratings`** / **`books_ratings_link`**: Star ratings
- **`languages`** / **`books_languages_link`**: Language codes

---

## App Structure (Xcode Project)

```
CalibreRead/
├── CalibreReadApp.swift              # @main App entry point
├── Package.swift                     # SPM dependencies
│
├── Models/
│   ├── CalibreLibrary.swift          # Library loader & metadata.db reader
│   ├── CalibreBook.swift             # Book model (from Calibre DB)
│   ├── CalibreAuthor.swift           # Author model
│   ├── CalibreSeries.swift           # Series model
│   ├── ReadingProgress.swift         # SwiftData model — user's reading state
│   └── Bookmark.swift                # SwiftData model — user bookmarks
│
├── Services/
│   ├── LibraryService.swift          # Business logic for querying library
│   ├── EPUBService.swift             # EPUB extraction & chapter loading
│   └── SearchService.swift           # Full-text metadata search
│
├── Views/
│   ├── Library/
│   │   ├── LibraryView.swift         # Main library browser (grid + list)
│   │   ├── BookGridItem.swift        # Cover thumbnail card
│   │   ├── BookListRow.swift         # List row with metadata
│   │   ├── SidebarView.swift         # Authors, tags, series navigation
│   │   └── BookDetailView.swift      # Book info sheet/panel
│   │
│   ├── Reader/
│   │   ├── ReaderView.swift          # Container for EPUB or PDF reader
│   │   ├── EPUBReaderView.swift      # WKWebView-based EPUB renderer
│   │   ├── PDFReaderView.swift       # PDFKit-based PDF renderer
│   │   ├── ReaderToolbar.swift       # Font size, theme, TOC controls
│   │   └── TableOfContentsView.swift # Chapter navigation
│   │
│   └── Settings/
│       └── SettingsView.swift        # Library path, appearance prefs
│
├── Utilities/
│   ├── WebViewRepresentable.swift    # NSViewRepresentable for WKWebView
│   └── PDFViewRepresentable.swift    # NSViewRepresentable for PDFView
│
└── Resources/
    ├── Assets.xcassets
    └── reader.css                    # Default EPUB reading stylesheet
```

---

## Implementation Phases

### Phase 1 — Project Setup & Calibre Library Reading
**Goal**: Open a Calibre library folder and display the book catalog.

1. Create Xcode project (macOS App, SwiftUI lifecycle, Swift 6)
2. Add SPM dependencies: SQLite.swift, EPUBKit
3. Implement `CalibreLibrary` — open `metadata.db` read-only, query books/authors/tags/series
4. Implement models: `CalibreBook`, `CalibreAuthor`, `CalibreSeries`
5. Folder picker to select Calibre library root (with security-scoped bookmark for persistent access)
6. Basic `LibraryView` showing book covers in a grid
7. Load cover images from `{library_root}/{book.path}/cover.jpg`

**Deliverable**: App opens a Calibre library and displays a browsable grid of book covers with titles.

### Phase 2 — Library Browsing & Navigation
**Goal**: Rich browsing experience with filtering, sorting, and search.

1. Sidebar with sections: Authors, Series, Tags, Publishers, Languages
2. Click sidebar item to filter the book grid
3. Sort options: title, author, date added, publication date, rating
4. Search bar — filter by title, author, series, tags
5. Toggle between grid view and list view
6. Book detail panel — click a book to see: cover, title, author, series position, description, formats available, tags, rating
7. Display format badges (EPUB, PDF, etc.) on each book

**Deliverable**: Full library navigation with sidebar, search, sort, and book details.

### Phase 3 — EPUB Reader
**Goal**: Read EPUB books with a comfortable reading experience.

1. Extract EPUB (ZIP) to a temporary directory
2. Parse with EPUBKit — get metadata, spine (reading order), TOC
3. `EPUBReaderView` — load chapter XHTML into WKWebView
4. Inject custom CSS (`reader.css`) for typography, margins, and theming
5. Chapter navigation: next/previous via buttons and keyboard arrows
6. Table of contents popover/sidebar
7. Font size adjustment (inject CSS changes via JavaScript)
8. Reading themes: light, sepia, dark (inject CSS)
9. Scroll-based reading (continuous scroll within a chapter)

**Deliverable**: Functional EPUB reader with chapter navigation, TOC, and theming.

### Phase 4 — PDF Reader
**Goal**: Read PDF books using native PDFKit.

1. `PDFReaderView` wrapping `PDFView` in `NSViewRepresentable`
2. Auto-scaling, zoom controls
3. Page navigation (go to page, thumbnail sidebar)
4. Text selection and copy support (built into PDFKit)

**Deliverable**: PDF reader with zoom, navigation, and text selection.

### Phase 5 — Reading State & Bookmarks
**Goal**: Remember where the user left off and support bookmarks.

1. SwiftData models: `ReadingProgress` (book id, format, position/chapter/page, last read date)
2. Auto-save reading position on chapter change, scroll, and app close
3. Resume reading from last position when reopening a book
4. Bookmark system — save named bookmarks to specific positions
5. "Continue Reading" section on the library home screen showing recently read books
6. Mark books as read/unread

**Deliverable**: Persistent reading state with auto-resume and bookmarks.

### Phase 6 — Polish & macOS Integration
**Goal**: Feel like a proper native macOS app.

1. Keyboard shortcuts: Space (page down), arrow keys (chapter nav), Cmd+F (search), Cmd+[ / ] (back/forward)
2. Menu bar integration (File > Open Library, View > Toggle Sidebar, etc.)
3. Multiple windows support — open multiple books simultaneously
4. Full-screen reading mode
5. Touch Bar support (if applicable)
6. Drag and drop — drag a book from Finder onto the app to locate it in the library
7. App icon and visual polish
8. Proper window restoration (reopen last state on launch)

**Deliverable**: Polished macOS app with keyboard shortcuts, menus, and multi-window support.

---

## Key Design Decisions

### Read-Only Approach
The app never writes to the Calibre library or `metadata.db`. All user data (reading progress, bookmarks, preferences) is stored separately in the app's own SwiftData store. This means:
- No risk of corrupting the Calibre library
- The library can be on a network drive or synced folder
- Calibre and this app can coexist without conflicts

### Security-Scoped Bookmarks
macOS sandboxed apps need permission to access user-selected folders. We use security-scoped bookmarks to persist access to the Calibre library folder across app launches without re-prompting.

### EPUB Rendering via WKWebView
EPUB content is XHTML+CSS — a web view is the only practical way to render it with full fidelity. We inject our own stylesheet for reading comfort while preserving the book's intended formatting.

### Supported Formats (Initial)
- **EPUB** — Primary format, full reader support
- **PDF** — Full reader support via PDFKit
- Other formats (MOBI, AZW3, etc.) are out of scope for v1. Users can convert to EPUB in Calibre.

---

## SPM Dependencies

| Package | Purpose | License |
|---------|---------|---------|
| [SQLite.swift](https://github.com/stephencelis/SQLite.swift) | Read-only access to Calibre's metadata.db | MIT |
| [EPUBKit](https://github.com/witekbobrowski/EPUBKit) | Parse EPUB files (metadata, spine, TOC) | MIT |

Minimal dependency footprint — only two external packages.

---

## Future Considerations (Post-v1)
- Annotations and highlights (stored in SwiftData, not in the Calibre DB)
- Text-to-speech integration
- OPDS catalog support for remote Calibre servers (calibre-server / Calibre-Web)
- Collections / shelves (user-created groupings beyond Calibre's tags)
- Reading statistics (time spent, pages read)
- Export annotations as Markdown
