import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case sepia = "Sepia"
    case dark = "Dark"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .light: return "sun.max"
        case .sepia: return "doc.richtext"
        case .dark: return "moon"
        }
    }

    /// CSS injected into foliate-js content iframes via `renderer.setStyles()`.
    /// Only typography and colors — foliate-js manages layout, columns, and overflow.
    func css(fontSize: Int) -> String {
        let (bg, fg, linkColor) = colors
        return """
        body {
            font-family: 'Iowan Old Style', 'Palatino', 'Georgia', 'Hiragino Mincho ProN', 'YuMincho', serif !important;
            font-size: \(fontSize)px !important;
            line-height: 1.5 !important;
            letter-spacing: 0.01em !important;
            word-spacing: 0.05em !important;
            text-rendering: optimizeLegibility !important;
            -webkit-font-smoothing: antialiased !important;
            background-color: \(bg) !important;
            color: \(fg);
            text-align: justify !important;
            -webkit-hyphens: auto !important;
            hyphens: auto !important;
        }
        img {
            display: block !important;
            max-width: 100% !important;
            max-height: 85vh !important;
            width: auto !important;
            height: auto !important;
            object-fit: contain !important;
            margin-left: auto !important;
            margin-right: auto !important;
            break-inside: avoid !important;\(self != .dark ? "\n            mix-blend-mode: multiply !important;" : "")
        }
        p, li, blockquote, dd {
            orphans: 2 !important;
            widows: 2 !important;
            hanging-punctuation: allow-end last;
        }
        h1, h2, h3, h4, h5, h6 {
            line-height: 1.3 !important;
            margin-top: 1.2em !important;
            margin-bottom: 0.4em !important;
            break-after: avoid !important;
            text-indent: 0 !important;
        }
        h1 { font-size: 1.6em !important; }
        h2 { font-size: 1.35em !important; }
        h3 { font-size: 1.15em !important; }
        a {
            color: \(linkColor) !important;
            text-decoration: none !important;
        }
        blockquote {
            border-inline-start: 3px solid \(fg) !important;
            opacity: 0.85 !important;
            margin: 0.8em 0 0.8em 0.5em !important;
            padding-inline-start: 1em !important;
            break-inside: avoid !important;
        }
        pre, code {
            font-family: 'SF Mono', 'Menlo', monospace !important;
            font-size: 0.85em !important;
        }
        pre {
            white-space: pre-wrap !important;
            padding: 1em !important;
            border-radius: 6px !important;
            background: rgba(128,128,128,0.1) !important;
            break-inside: avoid !important;
        }
        table {
            border-collapse: collapse !important;
            max-width: 100% !important;
            break-inside: avoid !important;
        }
        td, th {
            padding: 0.4em 0.6em !important;
            border: 1px solid rgba(128,128,128,0.3) !important;
        }
        hr {
            border: none !important;
            border-top: 1px solid rgba(128,128,128,0.3) !important;
            margin: 1.5em 0 !important;
        }
        sup { line-height: 0 !important; }
        """
    }

    private var colors: (bg: String, fg: String, link: String) {
        switch self {
        case .light: return ("#ffffff", "#2d2d2d", "#4a6fa5")
        case .sepia: return ("#faf4e8", "#4a3728", "#8b6914")
        case .dark: return ("#1c1c1e", "#d1d1d6", "#6b9bd2")
        }
    }

    var swiftUIBackground: Color {
        switch self {
        case .light: return Color(red: 1, green: 1, blue: 1)
        case .sepia: return Color(red: 0.98, green: 0.957, blue: 0.91)
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.118)
        }
    }

    var swiftUIForeground: Color {
        switch self {
        case .light: return Color(red: 0.176, green: 0.176, blue: 0.176)
        case .sepia: return Color(red: 0.29, green: 0.216, blue: 0.157)
        case .dark: return Color(red: 0.82, green: 0.82, blue: 0.84)
        }
    }

    var swiftUISecondary: Color {
        switch self {
        case .light: return Color(red: 0.35, green: 0.35, blue: 0.37)
        case .sepia: return Color(red: 0.40, green: 0.33, blue: 0.24)
        case .dark: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}
