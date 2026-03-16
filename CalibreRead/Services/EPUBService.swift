import Foundation
import EPUBKit

/// Handles EPUB file extraction, parsing, and chapter loading.
final class EPUBService {
    let extractedURL: URL
    private let libraryRoot: URL
    private let contentDirectory: URL
    private let parsedTitle: String?
    private let parsedAuthor: String?

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

        // Try EPUBKit first, fall back to manual parsing for EPUB 3 without NCX
        do {
            let document = try EPUBParser().parse(documentAt: bookURL)
            self.contentDirectory = document.contentDirectory
            self.parsedTitle = document.title
            self.parsedAuthor = document.author
            self.chapters = EPUBService.buildChapters(
                spine: document.spine,
                manifest: document.manifest,
                contentDir: document.contentDirectory
            )
            self.tableOfContents = EPUBService.buildTOC(
                toc: document.tableOfContents,
                contentDir: document.contentDirectory,
                fallbackChapters: self.chapters
            )
        } catch {
            // If EPUBKit fails (commonly tableOfContentsMissing for EPUB 3),
            // fall back to manual OPF parsing
            let fallback = try EPUBService.parseFallback(bookURL: bookURL)
            self.contentDirectory = fallback.contentDirectory
            self.parsedTitle = fallback.title
            self.parsedAuthor = fallback.author
            self.chapters = fallback.chapters
            self.tableOfContents = fallback.tableOfContents
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: extractedURL)
    }

    var title: String {
        parsedTitle ?? "Unknown Title"
    }

    var author: String {
        parsedAuthor ?? "Unknown Author"
    }

    /// The root content directory of the parsed EPUB — used to grant WKWebView
    /// read access so that images and other resources load correctly.
    var contentRootURL: URL {
        document.contentDirectory
    }

    func chapterFileURL(for chapter: Chapter) -> URL {
        chapter.fileURL
    }

    // MARK: - Fallback EPUB 3 parser

    private struct FallbackResult {
        let contentDirectory: URL
        let title: String?
        let author: String?
        let chapters: [Chapter]
        let tableOfContents: [Chapter]
    }

    /// Manually parses an EPUB when EPUBKit fails (e.g. EPUB 3 without NCX TOC).
    /// Extracts the ZIP, reads container.xml to find the OPF, then parses the OPF
    /// for spine/manifest to build the chapter list.
    private static func parseFallback(bookURL: URL) throws -> FallbackResult {
        // 1. Unzip the EPUB
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalibreRead-fallback")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", bookURL.path, "-d", extractDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EPUBError.failedToParse(
                parserError: "Failed to extract EPUB archive (unzip exit code \(process.terminationStatus))",
                details: "Path: \(bookURL.path)"
            )
        }

        // 2. Read container.xml to find OPF path
        let containerURL = extractDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        let containerData = try Data(contentsOf: containerURL)
        let containerXML = try XMLDocument(data: containerData)

        // Find rootfile full-path — handle both namespaced and non-namespaced
        let opfRelativePath: String
        if let rootfiles = try containerXML.nodes(forXPath: "//*[local-name()='rootfile']").first as? XMLElement,
           let fullPath = rootfiles.attribute(forName: "full-path")?.stringValue {
            opfRelativePath = fullPath
        } else {
            throw EPUBError.failedToParse(
                parserError: "Could not find rootfile in container.xml",
                details: "Path: \(bookURL.path)"
            )
        }

        let opfURL = extractDir.appendingPathComponent(opfRelativePath)
        let contentDir = opfURL.deletingLastPathComponent()

        // 3. Parse OPF
        let opfData = try Data(contentsOf: opfURL)
        let opfXML = try XMLDocument(data: opfData)

        // Extract title and author from metadata
        let titleNode = try opfXML.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='title']").first
        let authorNode = try opfXML.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='creator']").first
        let title = titleNode?.stringValue
        let author = authorNode?.stringValue

        // 4. Build manifest: id -> (href, mediaType)
        let manifestNodes = try opfXML.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        var manifest: [String: (href: String, mediaType: String, properties: String?)] = [:]
        for node in manifestNodes {
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "id")?.stringValue,
                  let href = element.attribute(forName: "href")?.stringValue else { continue }
            let mediaType = element.attribute(forName: "media-type")?.stringValue ?? ""
            let properties = element.attribute(forName: "properties")?.stringValue
            manifest[id] = (href: href, mediaType: mediaType, properties: properties)
        }

        // 5. Build spine
        let spineNodes = try opfXML.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
        var chapters: [Chapter] = []
        for (index, node) in spineNodes.enumerated() {
            guard let element = node as? XMLElement,
                  let idref = element.attribute(forName: "idref")?.stringValue,
                  let item = manifest[idref] else { continue }
            let fileURL = contentDir.appendingPathComponent(item.href)
            chapters.append(Chapter(
                id: index,
                title: "Chapter \(index + 1)",
                href: item.href,
                fileURL: fileURL
            ))
        }

        // 6. Try to build TOC from EPUB 3 nav document
        var toc: [Chapter] = []
        let navItem = manifest.values.first { $0.properties?.contains("nav") == true }
        if let navItem = navItem {
            let navURL = contentDir.appendingPathComponent(navItem.href)
            if let navData = try? Data(contentsOf: navURL),
               let navDoc = try? XMLDocument(data: navData, options: [.documentTidyHTML]) {
                // Find the <nav epub:type="toc"> element's <ol>
                let navEntries = try? navDoc.nodes(forXPath: "//*[local-name()='nav']//*[local-name()='ol']/*[local-name()='li']")
                if let entries = navEntries {
                    for (index, node) in entries.enumerated() {
                        guard let li = node as? XMLElement else { continue }
                        let anchors = try? li.nodes(forXPath: ".//*[local-name()='a']")
                        guard let anchor = anchors?.first as? XMLElement,
                              let href = anchor.attribute(forName: "href")?.stringValue else { continue }
                        let label = anchor.stringValue ?? "Chapter \(index + 1)"
                        let baseHref = href.components(separatedBy: "#").first ?? href
                        let fileURL = contentDir.appendingPathComponent(baseHref)
                        toc.append(Chapter(
                            id: index,
                            title: label,
                            href: href,
                            fileURL: fileURL
                        ))
                    }
                }
            }
        }

        // Fall back to chapters if we couldn't parse the nav TOC
        if toc.isEmpty {
            toc = chapters
        }

        return FallbackResult(
            contentDirectory: contentDir,
            title: title,
            author: author,
            chapters: chapters,
            tableOfContents: toc
        )
    }

    // MARK: - Chapter building (from EPUBKit types)

    private static func buildChapters(
        spine: EPUBSpine,
        manifest: EPUBManifest,
        contentDir: URL
    ) -> [Chapter] {
        var chapters: [Chapter] = []
        for (index, spineItem) in spine.items.enumerated() {
            let itemId = spineItem.idref
            if let manifestItem = manifest.items[itemId] {
                let href = manifestItem.path
                let fileURL = contentDir.appendingPathComponent(href)
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

    private static func buildTOC(
        toc: EPUBTableOfContents,
        contentDir: URL,
        fallbackChapters: [Chapter]
    ) -> [Chapter] {
        guard let subTable = toc.subTable, !subTable.isEmpty else { return fallbackChapters }

        return subTable.enumerated().map { index, item in
            let href = item.item ?? ""
            let baseHref = href.components(separatedBy: "#").first ?? href
            let fileURL = contentDir.appendingPathComponent(baseHref)
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
    case failedToParse(parserError: String, details: String)
    case chapterNotFound

    var errorDescription: String? {
        switch self {
        case .failedToParse(let parserError, let details):
            return "Failed to parse EPUB file.\n\nParser error: \(parserError)\n\n\(details)"
        case .chapterNotFound: return "Chapter not found."
        }
    }
}
