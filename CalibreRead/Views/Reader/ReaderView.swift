import SwiftUI

struct ReaderView: View {
    let book: CalibreBook
    let libraryRoot: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let format = book.preferredFormat {
                switch format.format {
                case "EPUB":
                    if let url = book.fileURL(libraryRoot: libraryRoot, format: format) {
                        EPUBReaderView(bookURL: url, libraryRoot: libraryRoot, bookTitle: book.title, bookId: book.uuid)
                    } else {
                        errorView("Could not locate EPUB file.")
                    }
                case "PDF":
                    if let url = book.fileURL(libraryRoot: libraryRoot, format: format) {
                        PDFReaderView(url: url, bookTitle: book.title)
                    } else {
                        errorView("Could not locate PDF file.")
                    }
                default:
                    errorView("Unsupported format: \(format.format). Convert to EPUB or PDF in Calibre.")
                }
            } else {
                errorView("No readable format found for this book.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
