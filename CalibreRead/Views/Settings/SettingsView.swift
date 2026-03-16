import SwiftUI

struct SettingsView: View {
    @Environment(LibraryManager.self) private var library
    @State private var libraryPath: String = ""

    var body: some View {
        Form {
            Section("Calibre Library") {
                HStack {
                    TextField("Library Path", text: $libraryPath)
                        .disabled(true)

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.title = "Select your Calibre library folder"
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false

                        if panel.runModal() == .OK, let url = panel.url {
                            library.libraryURL = url
                            libraryPath = url.path
                        }
                    }
                }

                if library.isLoaded {
                    Text("\(library.books.count) books loaded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
        .onAppear {
            libraryPath = library.libraryURL?.path ?? ""
        }
    }
}
