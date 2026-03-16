import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let url: URL
    let bookTitle: String

    @State private var currentPage = 0
    @State private var pageCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(bookTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if pageCount > 0 {
                    Text("Page \(currentPage + 1) of \(pageCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            PDFReaderKitView(url: url) { page, total in
                currentPage = page
                pageCount = total
            }
        }
    }
}
