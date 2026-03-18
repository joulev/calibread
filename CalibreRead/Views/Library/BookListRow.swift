import SwiftUI

struct BookListRow: View {
    let book: CalibreBook
    let libraryRoot: URL

    var body: some View {
        HStack(spacing: 12) {
            CoverImageView(
                book: book,
                libraryRoot: libraryRoot,
                placeholderIconFont: .caption
            )
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(book.authorNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let series = book.seriesDescription {
                Text(series)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            FormatBadgeRow(formats: book.formats)
        }
        .padding(.vertical, 4)
    }
}
