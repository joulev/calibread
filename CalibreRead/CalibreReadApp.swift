import SwiftUI
import SwiftData

@main
struct CalibreReadApp: App {
    @State private var library = LibraryManager()

    var body: some Scene {
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
