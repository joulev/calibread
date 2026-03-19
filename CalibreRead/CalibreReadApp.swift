import SwiftUI
import SwiftData

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .showLibraryWindow, object: nil)
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let recentBooks = RecentBooksManager.shared.recentBooks
        guard !recentBooks.isEmpty else { return nil }

        let menu = NSMenu()
        for (index, book) in recentBooks.enumerated() {
            let item = NSMenuItem(title: book.title.truncated(toWidth: 350), action: #selector(openRecentBook(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    @objc func openRecentBook(_ sender: NSMenuItem) {
        let books = RecentBooksManager.shared.recentBooks
        guard sender.tag < books.count else { return }
        NotificationCenter.default.post(name: .openRecentBook, object: books[sender.tag])
    }
}

extension Notification.Name {
    static let showLibraryWindow = Notification.Name("showLibraryWindow")
    static let openRecentBook = Notification.Name("openRecentBook")
}

@main
struct CalibreReadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryManager()

    var body: some Scene {
        // Main library window (single instance)
        Window("Calibread", id: "library") {
            ContentView()
                .environment(library)
                .onAppear {
                    library.restoreSavedLibrary()
                }
        }
        .modelContainer(for: [ReadingProgress.self, BookmarkEntry.self])
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Library...") {
                    openLibrary()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Reload Library") {
                    if let url = library.libraryURL {
                        library.loadLibrary(from: url)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!library.isLoaded)

                Divider()

                OpenRecentMenu()
            }
        }

        // Reader windows — each opened book gets its own window
        WindowGroup(for: BookWindowData.self) { $data in
            if let data {
                BookReaderWindow(data: data, libraryRoot: library.libraryURL)
                    .environment(library)
            }
        }
        .modelContainer(for: [ReadingProgress.self, BookmarkEntry.self])
        .windowToolbarStyle(.unified)
        .defaultSize(width: 750, height: 1050)

        Settings {
            SettingsView()
                .environment(library)
        }
    }

    private func openLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Select your Calibre library folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            library.libraryURL = url
        }
    }
}

/// "Open Recent" submenu for the File menu.
private struct OpenRecentMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let recentBooks = RecentBooksManager.shared.recentBooks
        Menu("Open Recent") {
            if recentBooks.isEmpty {
                Text("No Recent Books")
            } else {
                ForEach(recentBooks, id: \.uuid) { book in
                    Button(book.title.truncated(toWidth: 350)) {
                        openWindow(value: book)
                    }
                }
            }
        }
    }
}

/// Wrapper view for the reader window that resolves file URLs from BookWindowData.
private struct BookReaderWindow: View {
    let data: BookWindowData
    let libraryRoot: URL?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let libraryRoot {
                let fileURL = data.fileURL(libraryRoot: libraryRoot)
                switch data.formatType {
                case "EPUB":
                    EPUBReaderView(
                        bookURL: fileURL,
                        libraryRoot: libraryRoot,
                        bookTitle: data.title,
                        bookId: data.uuid,
                        onClose: { dismiss() }
                    )
                case "PDF":
                    PDFReaderView(url: fileURL, bookTitle: data.title)
                default:
                    Text("Unsupported format: \(data.formatType)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No library is open. Open a library first.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLibraryWindow)) { _ in
            openWindow(id: "library")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentBook)) { notification in
            if let book = notification.object as? BookWindowData {
                openWindow(value: book)
            }
        }
    }
}
