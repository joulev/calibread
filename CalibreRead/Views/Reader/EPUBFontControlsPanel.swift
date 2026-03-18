import SwiftUI

struct EPUBFontControlsPanel: View {
    @Binding var fontSize: Int
    @Binding var theme: ReaderTheme

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
