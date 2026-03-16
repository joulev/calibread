# CalibreRead — Implementation Plan

## Status

Phases 1–5 are implemented and shipping. Phase 6 is partially done (menu bar commands). The app builds and runs on macOS 26.

## Completed

### Phase 1 — Project Setup & Calibre Library Reading
- Xcode project with SPM dependencies (SQLite.swift, EPUBKit)
- `CalibreDatabase` reads `metadata.db` — books, authors, tags, series, formats, comments, ratings, publishers
- Folder picker to select library root, path persisted in UserDefaults
- Book cover loading from `{library_root}/{book.path}/cover.jpg`

### Phase 2 — Library Browsing & Navigation
- `NavigationSplitView` with sidebar (Authors, Series, Tags)
- Grid view with cover thumbnails, list view with metadata rows
- Search across title, author, series, tags
- Sort by title, author, date added, date published
- Book detail inspector panel with cover, metadata, star ratings, tags, HTML description
- Format badges (EPUB, PDF, etc.)

### Phase 3 — EPUB Reader
- EPUBKit parses EPUB spine, manifest, and table of contents
- WKWebView renders chapter XHTML with CSS injection
- Light / Sepia / Dark themes
- Font size controls (12–32px)
- Chapter navigation (previous/next buttons + TOC sheet)
- Scroll position tracking via JavaScript bridge

### Phase 4 — PDF Reader
- PDFKit `PDFView` wrapped in `NSViewRepresentable`
- Auto-scaling, page change tracking
- Page count display

### Phase 5 — Reading State
- SwiftData models: `ReadingProgress`, `BookmarkEntry`
- Auto-save reading position on chapter change and reader close
- Auto-restore position when reopening a book

## Remaining

### Phase 6 — Polish & macOS Integration (partial)
Done:
- Menu bar: Open Library (Cmd+Shift+O), Reload Library (Cmd+R)
- Settings window

Remaining:
- [ ] Liquid glass UI (macOS 26 design language)
- [ ] Keyboard shortcuts in reader (Space, arrows, Cmd+F)
- [ ] Multi-window support (open books in separate windows)
- [ ] Full-screen reading mode
- [ ] Window restoration (reopen last state on launch)
- [ ] App icon

### Future Features
- [ ] Bookmarks UI (data model exists, needs create/view/delete UI)
- [ ] "Continue Reading" section on library home screen
- [ ] Annotations and highlights
- [ ] Text-to-speech
- [ ] OPDS catalog support (calibre-server / Calibre-Web)
- [ ] Reading statistics
- [ ] Export annotations as Markdown

## Calibre Database Reference

```
metadata.db tables:
├── books (id, title, sort, author_sort, timestamp, pubdate, series_index, path, uuid, has_cover)
├── authors (id, name, sort, link)
├── tags (id, name)
├── series (id, name, sort)
├── publishers (id, name, sort)
├── ratings (id, rating)
├── languages (id, lang_code)
├── comments (id, book, text)  — HTML descriptions
├── data (id, book, format, name, uncompressed_size)  — format files
├── books_authors_link (book, author)
├── books_tags_link (book, tag)
├── books_series_link (book, series)
├── books_publishers_link (book, publisher)
├── books_ratings_link (book, rating)
└── books_languages_link (book, lang_code, item_order)
```

Book files live at: `{library_root}/{books.path}/{data.name}.{data.format.lowercased()}`
Cover images at: `{library_root}/{books.path}/cover.jpg`
