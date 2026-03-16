import SwiftUI

struct BookListRow: View {
    let book: CalibreBook
    let libraryRoot: URL

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
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

            HStack(spacing: 4) {
                ForEach(book.formats, id: \.id) { format in
                    Text(format.format)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        if let url = book.coverURL(libraryRoot: libraryRoot),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}
