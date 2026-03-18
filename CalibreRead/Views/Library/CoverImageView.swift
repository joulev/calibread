import SwiftUI

/// Reusable cover image view with a placeholder fallback.
struct CoverImageView: View {
    let book: CalibreBook
    let libraryRoot: URL
    var contentMode: ContentMode = .fill
    var placeholderIconFont: Font = .largeTitle
    var showTitleInPlaceholder = false

    var body: some View {
        if let url = book.coverURL(libraryRoot: libraryRoot),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(placeholderIconFont)
                        .foregroundStyle(.secondary)
                    if showTitleInPlaceholder {
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
}
