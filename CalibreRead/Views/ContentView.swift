import SwiftUI

struct ContentView: View {
    @Environment(LibraryManager.self) private var library
    @State private var openedBook: CalibreBook?

    var body: some View {
        if library.isLoaded {
            ZStack {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    LibraryView(openedBook: $openedBook)
                }
                .frame(minWidth: 800, minHeight: 500)

                if let book = openedBook {
                    ReaderView(book: book, libraryRoot: library.libraryURL!) {
                        openedBook = nil
                    }
                    .transition(.opacity)
                }
            }
        } else {
            WelcomeView()
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

            Text("CalibreRead")
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
