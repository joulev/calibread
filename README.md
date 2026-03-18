# CalibreRead

A native macOS SwiftUI ereader for Calibre libraries. Opens your existing Calibre library folder and lets you read EPUB and PDF books with a clean, native interface. Read-only — never modifies your library.

## Features

- **Library browser** — grid and list views with cover art, search, sort, and sidebar filtering by author/series/tag
- **EPUB reader** — WKWebView rendering with light/sepia/dark themes, font size controls, chapter navigation, and table of contents
- **PDF reader** — native PDFKit with page tracking
- **Reading progress** — automatically saves and restores your position in each book
- **Calibre compatible** — reads `metadata.db` directly, supports all Calibre metadata (authors, series, tags, ratings, descriptions)

## Requirements

- macOS 26 (Tahoe)
- A Calibre library on your filesystem

## Install

Download `CalibreRead.zip` from the latest [GitHub Release](../../releases/latest), unzip, then run once in Terminal:

```bash
xattr -cr CalibreRead.app
```

Move to `/Applications` and open.

## Build from Source

Open `CalibreRead.xcodeproj` in Xcode 26. SPM dependencies (SQLite.swift) resolve automatically. Build and run.

## How It Works

The app reads your Calibre library's `metadata.db` (SQLite) to get book metadata, covers, and file paths. EPUB files are rendered in a WKWebView using [foliate-js](https://github.com/johnfactotum/foliate-js) (vendored), which handles parsing, pagination, and display. PDFs are rendered with native PDFKit. Reading progress is stored in the app's own SwiftData database — your Calibre library is never modified.
