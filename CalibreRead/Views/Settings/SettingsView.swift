import SwiftUI

struct SettingsView: View {
    @Environment(LibraryManager.self) private var library
    @State private var libraryPath: String = ""
    @AppStorage("readerTheme") private var readerTheme: ReaderTheme = .sepia
    @AppStorage("readerFontSize") private var fontSize = ReaderConstants.defaultFontSize
    @AppStorage("readerMainFont") private var mainFont = ""
    @AppStorage("readerSupplementalFont") private var supplementalFont = ""

    private static let systemFonts: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        Form {
            Section("Reader") {
                Picker("Theme", selection: $readerTheme) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Label(theme.rawValue, systemImage: theme.icon)
                    }
                }

                Picker("Font Size", selection: $fontSize) {
                    ForEach(stride(from: ReaderConstants.minFontSize, through: ReaderConstants.maxFontSize, by: ReaderConstants.fontSizeStep).map { $0 }, id: \.self) { size in
                        Text("\(size)px").tag(size)
                    }
                }

                settingsFontPicker("Main Font", defaultName: ReaderConstants.defaultMainFont, selection: $mainFont)
                settingsFontPicker("Supplemental Font", defaultName: ReaderConstants.defaultSupplementalFont, selection: $supplementalFont)
            }

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

    private func settingsFontPicker(_ label: String, defaultName: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text("Default (\(defaultName))")
                .font(.custom(defaultName, size: 13))
                .tag("")
            Divider()
            ForEach(Self.systemFonts, id: \.self) { font in
                Text(font)
                    .font(.custom(font, size: 13))
                    .tag(font)
            }
        }
    }
}
