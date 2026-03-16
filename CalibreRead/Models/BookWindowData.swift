import Foundation

/// Lightweight, Codable data passed to openWindow to spawn a reader window.
struct BookWindowData: Codable, Hashable {
    let bookId: Int64
    let uuid: String
    let title: String
    let authorSort: String
    let path: String
    let formatName: String   // e.g. "Book Title - Author"
    let formatType: String   // e.g. "EPUB" or "PDF"

    init?(book: CalibreBook, libraryRoot: URL) {
        guard let format = book.preferredFormat else { return nil }
        self.bookId = book.id
        self.uuid = book.uuid
        self.title = book.title
        self.authorSort = book.authorSort
        self.path = book.path
        self.formatName = format.name
        self.formatType = format.format
    }

    func fileURL(libraryRoot: URL) -> URL {
        libraryRoot
            .appendingPathComponent(path)
            .appendingPathComponent("\(formatName).\(formatType.lowercased())")
    }
}
