import SwiftUI

/// Displays a row of format badges (e.g. EPUB, PDF) for a book.
struct FormatBadgeRow: View {
    let formats: [BookFormat]
    var fontSize: CGFloat = 10
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 2

    var body: some View {
        if !formats.isEmpty {
            HStack(spacing: 4) {
                ForEach(formats, id: \.id) { format in
                    Text(format.format)
                        .font(.system(size: fontSize, weight: .medium))
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }
}
