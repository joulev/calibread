import Foundation

/// Shared utility for matching EPUB chapter hrefs.
///
/// EPUB hrefs can be relative paths with or without fragment identifiers (#anchor).
/// The same chapter may be referenced with different path prefixes depending on
/// whether it comes from the spine, TOC, or nav document. This utility normalizes
/// and compares hrefs to handle these variations.
enum HrefMatcher {
    /// Strips the fragment identifier (#...) from an href, returning just the file path.
    static func baseHref(_ href: String) -> String {
        href.components(separatedBy: "#").first ?? href
    }

    /// Returns true if two hrefs refer to the same file, ignoring fragment identifiers
    /// and allowing suffix-based matches for relative vs absolute paths.
    static func matches(_ a: String, _ b: String) -> Bool {
        let baseA = baseHref(a)
        let baseB = baseHref(b)
        return baseA == baseB
            || baseA.hasSuffix("/\(baseB)")
            || baseB.hasSuffix("/\(baseA)")
    }

    /// Finds the first TOC entry whose href matches the given spine chapter href.
    static func findTOCEntry(for spineHref: String, in toc: [EPUBService.Chapter]) -> EPUBService.Chapter? {
        toc.first { matches(spineHref, $0.href) }
    }

    /// Finds the spine index that matches a TOC entry's href.
    static func findSpineIndex(for tocHref: String, in spine: [EPUBService.Chapter]) -> Int? {
        spine.firstIndex { matches(tocHref, $0.href) }
    }
}
