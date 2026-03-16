import SwiftUI

struct BookGridItem: View {
    let book: CalibreBook
    let libraryRoot: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverImage
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

            if !book.formats.isEmpty {
                HStack(spacing: 4) {
                    ForEach(book.formats) { format in
                        Text(format.format)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = book.coverURL(libraryRoot: libraryRoot),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(book.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}
