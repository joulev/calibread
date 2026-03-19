import SwiftUI

struct ContentView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if library.isLoaded {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    LibraryView()
                }
                .frame(minWidth: 800, minHeight: 500)
            } else {
                WelcomeView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentBook)) { notification in
            if let book = notification.object as? BookWindowData {
                openWindow(value: book)
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(LibraryManager.self) private var library

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Calibread")
                .font(.largeTitle.bold())

            Text("Open your Calibre library to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Open Calibre Library...") {
                openLibraryPicker()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if let error = library.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func openLibraryPicker() {
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
