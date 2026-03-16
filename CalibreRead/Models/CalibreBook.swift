import Foundation
import AppKit

/// Represents a book from the Calibre library database.
struct CalibreBook: Identifiable, Hashable {
    let id: Int64
    let title: String
    let sortTitle: String
    let authorSort: String
    let timestamp: Date?
    let pubdate: Date?
    let seriesIndex: Double
    let path: String
    let uuid: String
    let hasCover: Bool
    let lastModified: Date?

    var authors: [CalibreAuthor] = []
    var tags: [CalibreTag] = []
    var series: CalibreSeries?
    var formats: [BookFormat] = []
    var comment: String?
    var rating: Int?
    var languages: [String] = []
    var publisher: String?

    var authorNames: String {
        authors.map(\.name).joined(separator: ", ")
    }

    var seriesDescription: String? {
        guard let series else { return nil }
        let index = seriesIndex == floor(seriesIndex) ? String(Int(seriesIndex)) : String(seriesIndex)
        return "\(series.name) #\(index)"
    }

    func coverURL(libraryRoot: URL) -> URL? {
        guard hasCover else { return nil }
        return libraryRoot.appendingPathComponent(path).appendingPathComponent("cover.jpg")
    }

    func fileURL(libraryRoot: URL, format: BookFormat) -> URL? {
        let bookDir = libraryRoot.appendingPathComponent(path)
        return bookDir.appendingPathComponent("\(format.name).\(format.format.lowercased())")
    }

    var preferredFormat: BookFormat? {
        // Prefer EPUB, then PDF
        formats.first(where: { $0.format == "EPUB" })
            ?? formats.first(where: { $0.format == "PDF" })
            ?? formats.first
    }

    static func == (lhs: CalibreBook, rhs: CalibreBook) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct BookFormat: Identifiable, Hashable {
    let id: Int64
    let bookId: Int64
    let format: String
    let name: String
    let uncompressedSize: Int64

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: uncompressedSize, countStyle: .file)
    }
}
