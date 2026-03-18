# Calibread

A lightweight, minimal native macOS application to read books in your [Calibre](https://calibre-ebook.com) library.

<img width="1920" height="1080" alt="Screenshot 2026-03-18 at 12 40 52 PM" src="https://github.com/user-attachments/assets/e1f27406-2595-4259-b464-8cf1a925779f" />

---

> [!NOTE]  
> This app is fully built by Claude Code. It carries with it any risks that vibe coded apps have, although the source code is here for you to verify and check. I personally trust this app enough to use it as my reader over Books.app and Calibre's default reader.

## Features

- Read directly from your Calibre library: can be used as an alternative to Calibre's default reader. Start reading without having to export your books from Calibre
- EPUB reader powered by [foliate-js](https://github.com/johnfactotum/foliate-js)
- Support [Japanese vertical writing (tategaki)](https://en.wikipedia.org/wiki/Horizontal_and_vertical_writing_in_East_Asian_scripts) out of the box
- Specifically designed for Japanese light novels in both English and Japanese
- Minimal reader: no highlighting, no bookmarking. Not editing text when you copy or intervening with right click context menus like Books.app or other reader apps
- macOS 26 native design language

## Requirements

- macOS 26 (Tahoe)
- A Calibre library on your filesystem

## Install

1. First you need to have [Calibre](https://calibre-ebook.com) installed and set up a library there.

2. Download `Calibread.zip` from the latest [GitHub Release](../../releases/latest), unzip, then run once in Terminal:

   ```bash
   xattr -cr Calibread.app
   ```

   The above step is necessary to run the app, as I do not have an Apple developer account ($99/yr) to notarise the app for distribution.

3. Move to `/Applications` and open.

4. Select the Calibre library to read from and you are set. Typically your library location is `/Users/<username>/Calibre Library`.

## Build from Source

Open `CalibreRead.xcodeproj` in Xcode 26. SPM dependencies (SQLite.swift) resolve automatically. Build and run.

## How It Works

The app reads your Calibre library's `metadata.db` to get book data. It **never** modifies your Calibre library. To edit book metadata and so on, use Calibre.
