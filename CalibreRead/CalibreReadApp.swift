import SwiftUI
import SwiftData

@main
struct CalibreReadApp: App {
    @State private var library = LibraryManager()

    var body: some Scene {
        // Main library window
        WindowGroup {
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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 700)

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

/// Wrapper view for the reader window that resolves file URLs from BookWindowData.
private struct BookReaderWindow: View {
    let data: BookWindowData
    let libraryRoot: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
}
