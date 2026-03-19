import SwiftUI

struct EPUBFontControlsPanel: View {
    @Binding var fontSize: Int
    @Binding var theme: ReaderTheme
    @Binding var mainFont: String
    @Binding var supplementalFont: String

    private static let systemFonts: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                fontSizeButton(
                    label: "A",
                    labelFont: .system(size: 14),
                    action: { fontSize = max(ReaderConstants.minFontSize, fontSize - ReaderConstants.fontSizeStep) }
                )

                Text("\(fontSize)px")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                fontSizeButton(
                    label: "A",
                    labelFont: .system(size: 18, weight: .medium),
                    action: { fontSize = min(ReaderConstants.maxFontSize, fontSize + ReaderConstants.fontSizeStep) }
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                fontPickerRow("Main font", defaultName: ReaderConstants.defaultMainFont, selection: $mainFont)
                fontPickerRow("Supplemental font", defaultName: ReaderConstants.defaultSupplementalFont, selection: $supplementalFont)
            }

            HStack(spacing: 10) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Button {
                        theme = t
                    } label: {
                        Circle()
                            .fill(t.swiftUIBackground)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        theme == t ? Color.accentColor : Color.gray.opacity(0.3),
                                        lineWidth: theme == t ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private func fontPickerRow(_ label: String, defaultName: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

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
            .labelsHidden()
            .buttonSizing(.flexible)
        }
    }

    private func fontSizeButton(label: String, labelFont: Font, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(labelFont)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                )
        }
        .buttonStyle(.plain)
    }
}
