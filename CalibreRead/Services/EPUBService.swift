import Foundation
import EPUBKit

/// Handles EPUB file extraction, parsing, and chapter loading.
final class EPUBService {
    let document: EPUBDocument
    let extractedURL: URL
    private let libraryRoot: URL

    struct Chapter: Identifiable {
        let id: Int
        let title: String
        let href: String
        var fileURL: URL
    }

    private(set) var chapters: [Chapter] = []
    private(set) var tableOfContents: [Chapter] = []

    init(bookURL: URL, libraryRoot: URL) throws {
        self.libraryRoot = libraryRoot

        // Extract EPUB to a temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalibreRead")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        self.extractedURL = tempDir

        // Parse EPUB
        guard let doc = EPUBDocument(url: bookURL) else {
            throw EPUBError.failedToParse
        }
        self.document = doc

        // Build chapter list from spine
        self.chapters = buildChapters()
        self.tableOfContents = buildTOC()
    }

    deinit {
        try? FileManager.default.removeItem(at: extractedURL)
    }

    var title: String {
        document.title ?? "Unknown Title"
    }

    var author: String {
        document.author ?? "Unknown Author"
    }

    func chapterFileURL(for chapter: Chapter) -> URL {
        chapter.fileURL
    }

    // MARK: - Private

    private func buildChapters() -> [Chapter] {
        let spine = document.spine
        let manifest = document.manifest
        let contentDir = document.contentDirectory

        var chapters: [Chapter] = []
        for (index, spineItem) in spine.items.enumerated() {
            let itemId = spineItem.idref
            if let manifestItem = manifest.items[itemId] {
                let href = manifestItem.path
                let fileURL = contentDir
                    .appendingPathComponent(href)

                chapters.append(Chapter(
                    id: index,
                    title: "Chapter \(index + 1)",
                    href: href,
                    fileURL: fileURL
                ))
            }
        }
        return chapters
    }

    private func buildTOC() -> [Chapter] {
        let toc = document.tableOfContents
        let contentDir = document.contentDirectory

        guard let subTable = toc.subTable, !subTable.isEmpty else { return chapters }

        return subTable.enumerated().map { index, item in
            let href = item.item ?? ""
            let baseHref = href.components(separatedBy: "#").first ?? href
            let fileURL = contentDir
                .appendingPathComponent(baseHref)

            return Chapter(
                id: index,
                title: item.label,
                href: href,
                fileURL: fileURL
            )
        }
    }
}

enum EPUBError: LocalizedError {
    case failedToParse
    case chapterNotFound

    var errorDescription: String? {
        switch self {
        case .failedToParse: return "Failed to parse EPUB file."
        case .chapterNotFound: return "Chapter not found."
        }
    }
}
