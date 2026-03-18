import SwiftUI

struct BookGridItem: View {
    let book: CalibreBook
    let libraryRoot: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImageView(
                book: book,
                libraryRoot: libraryRoot,
                showTitleInPlaceholder: true
            )
            .frame(width: 160, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

            Text(book.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text(book.authorNames)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            FormatBadgeRow(formats: book.formats, fontSize: 9, horizontalPadding: 4, verticalPadding: 1)
        }
    }
}
