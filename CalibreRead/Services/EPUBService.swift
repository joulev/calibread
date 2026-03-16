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

        // Parse EPUB using EPUBParser directly to get real error details
        // (EPUBDocument(url:) uses try? which swallows the actual error)
        do {
            self.document = try EPUBParser().parse(documentAt: bookURL)
        } catch {
            throw EPUBError.failedToParse(
                parserError: "\(error)",
                details: EPUBService.gatherDiagnostics(for: bookURL)
            )
        }

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

    // MARK: - Diagnostics

    private static func gatherDiagnostics(for url: URL) -> String {
        var lines: [String] = []
        lines.append("Path: \(url.path)")

        let fm = FileManager.default

        // Check file exists and size
        guard fm.fileExists(atPath: url.path) else {
            lines.append("Error: File does not exist at path.")
            return lines.joined(separator: "\n")
        }

        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            lines.append("File size: \(size) bytes")
        }

        // Try to read as a ZIP archive (EPUBs are ZIP files)
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            // Check ZIP magic bytes (PK\x03\x04)
            if data.count >= 4 {
                let magic = Array(data.prefix(4))
                let isZip = magic == [0x50, 0x4B, 0x03, 0x04]
                lines.append("ZIP magic bytes: \(magic.map { String(format: "0x%02X", $0) }.joined(separator: " ")) (\(isZip ? "valid" : "INVALID - not a ZIP file"))")
            } else {
                lines.append("Error: File too small (\(data.count) bytes)")
            }
        } catch {
            lines.append("Error reading file: \(error.localizedDescription)")
        }

        // Try to inspect the EPUB structure via Process (unzip -l)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = ["-1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let files = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                lines.append("ZIP entries: \(files.count)")

                // Check for key EPUB files
                let hasContainer = files.contains { $0.hasSuffix("META-INF/container.xml") }
                let hasMimetype = files.contains { $0 == "mimetype" }
                let opfFiles = files.filter { $0.hasSuffix(".opf") }

                lines.append("Has mimetype: \(hasMimetype)")
                lines.append("Has META-INF/container.xml: \(hasContainer)")
                lines.append("OPF files: \(opfFiles.isEmpty ? "(none)" : opfFiles.joined(separator: ", "))")

                // Show first 20 entries for context
                let preview = files.prefix(20)
                lines.append("\nFirst \(preview.count) ZIP entries:")
                for entry in preview {
                    lines.append("  \(entry)")
                }
                if files.count > 20 {
                    lines.append("  ... and \(files.count - 20) more")
                }
            } else {
                lines.append("zipinfo failed (exit \(process.terminationStatus)): \(output.prefix(500))")
            }
        } catch {
            lines.append("Could not run zipinfo: \(error.localizedDescription)")
        }

        return lines.joined(separator: "\n")
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
