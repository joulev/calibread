import SwiftUI
import WebKit

struct EPUBWebView: NSViewRepresentable {
    let fileURL: URL
    let theme: ReaderTheme
    let fontSize: Int
    let onPageInfo: ((Int, Int) -> Void)?  // (currentPage, totalPages)

    @Binding var pageCommand: PageCommand

    enum PageCommand: Equatable {
        case none
        case next
        case previous
        case goTo(Double) // fraction 0...1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageInfo: onPageInfo)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "pageHandler")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.theme = theme
        context.coordinator.fontSize = fontSize

        loadContent(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPageInfo = onPageInfo

        if context.coordinator.currentURL != fileURL {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            loadContent(in: webView)
        } else if context.coordinator.theme != theme || context.coordinator.fontSize != fontSize {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            injectStyles(in: webView)
        }

        // Handle page commands
        switch pageCommand {
        case .next:
            webView.evaluateJavaScript("CalibreReader.nextPage()", completionHandler: nil)
            DispatchQueue.main.async { pageCommand = .none }
        case .previous:
            webView.evaluateJavaScript("CalibreReader.prevPage()", completionHandler: nil)
            DispatchQueue.main.async { pageCommand = .none }
        case .goTo(let fraction):
            webView.evaluateJavaScript("CalibreReader.goToFraction(\(fraction))", completionHandler: nil)
            DispatchQueue.main.async { pageCommand = .none }
        case .none:
            break
        }
    }

    private func loadContent(in webView: WKWebView) {
        let directory = fileURL.deletingLastPathComponent()
        webView.loadFileURL(fileURL, allowingReadAccessTo: directory)
    }

    private func injectStyles(in webView: WKWebView) {
        let css = theme.css(fontSize: fontSize)
        let js = """
        (function() {
            var style = document.getElementById('calibreread-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'calibreread-style';
                document.head.appendChild(style);
            }
            style.textContent = `\(css)`;
            setTimeout(function() { CalibreReader.recalculate(); }, 50);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var currentURL: URL?
        var onPageInfo: ((Int, Int) -> Void)?
        var theme: ReaderTheme = .light
        var fontSize: Int = 18

        init(onPageInfo: ((Int, Int) -> Void)?) {
            self.onPageInfo = onPageInfo
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL = webView.url

            let css = theme.css(fontSize: fontSize)
            let setupJS = """
            (function() {
                // Inject theme styles
                var style = document.getElementById('calibreread-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'calibreread-style';
                    document.head.appendChild(style);
                }
                style.textContent = `\(css)`;

                // Set up pagination engine
                var CalibreReader = {
                    currentPage: 0,
                    totalPages: 1,
                    pageWidth: 0,

                    recalculate: function() {
                        this.pageWidth = window.innerWidth;
                        var scrollWidth = document.documentElement.scrollWidth;
                        this.totalPages = Math.max(1, Math.round(scrollWidth / this.pageWidth));
                        this.currentPage = Math.min(this.currentPage, this.totalPages - 1);
                        this.reportPage();
                    },

                    reportPage: function() {
                        window.webkit.messageHandlers.pageHandler.postMessage({
                            current: this.currentPage + 1,
                            total: this.totalPages
                        });
                    },

                    goToPage: function(n) {
                        this.currentPage = Math.max(0, Math.min(n, this.totalPages - 1));
                        document.documentElement.scrollLeft = this.currentPage * this.pageWidth;
                        this.reportPage();
                    },

                    nextPage: function() {
                        if (this.currentPage < this.totalPages - 1) {
                            this.goToPage(this.currentPage + 1);
                            return true;
                        }
                        return false;
                    },

                    prevPage: function() {
                        if (this.currentPage > 0) {
                            this.goToPage(this.currentPage - 1);
                            return true;
                        }
                        return false;
                    },

                    goToFraction: function(f) {
                        var page = Math.round(f * (this.totalPages - 1));
                        this.goToPage(page);
                    },

                    getFraction: function() {
                        if (this.totalPages <= 1) return 0;
                        return this.currentPage / (this.totalPages - 1);
                    }
                };

                window.CalibreReader = CalibreReader;

                // Initial calculation after layout settles
                setTimeout(function() { CalibreReader.recalculate(); }, 100);

                // Recalculate on resize
                window.addEventListener('resize', function() {
                    setTimeout(function() { CalibreReader.recalculate(); }, 100);
                });

                // Handle keyboard navigation within the webview
                document.addEventListener('keydown', function(e) {
                    if (e.key === 'ArrowRight' || e.key === ' ') {
                        e.preventDefault();
                        var moved = CalibreReader.nextPage();
                        if (!moved) {
                            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'nextChapter' });
                        }
                    } else if (e.key === 'ArrowLeft') {
                        e.preventDefault();
                        var moved = CalibreReader.prevPage();
                        if (!moved) {
                            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'prevChapter' });
                        }
                    }
                });

                // Prevent native scroll
                document.addEventListener('wheel', function(e) { e.preventDefault(); }, { passive: false });
            })();
            """
            webView.evaluateJavaScript(setupJS, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pageHandler", let dict = message.body as? [String: Any] {
                if let current = dict["current"] as? Int, let total = dict["total"] as? Int {
                    DispatchQueue.main.async {
                        self.onPageInfo?(current, total)
                    }
                }
                if let action = dict["action"] as? String {
                    DispatchQueue.main.async {
                        if action == "nextChapter" {
                            self.onPageInfo?(-1, 0)  // signal: next chapter
                        } else if action == "prevChapter" {
                            self.onPageInfo?(-2, 0)  // signal: prev chapter
                        }
                    }
                }
            }
        }
    }
}

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

    func css(fontSize: Int) -> String {
        let (bg, fg, linkColor) = colors
        return """
        html {
            overflow: hidden !important;
            height: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        body {
            font-family: 'Iowan Old Style', 'Palatino', 'Georgia', serif !important;
            font-size: \(fontSize)px !important;
            line-height: 1.7 !important;
            letter-spacing: 0.01em !important;
            word-spacing: 0.05em !important;
            text-rendering: optimizeLegibility !important;
            -webkit-font-smoothing: antialiased !important;
            background-color: \(bg) !important;
            color: \(fg) !important;
            margin: 0 !important;
            padding: 40px 60px !important;
            box-sizing: border-box !important;
            height: 100vh !important;
            column-fill: auto !important;
            column-gap: 80px !important;
            column-width: calc(100vw - 200px) !important;
            overflow: hidden !important;
            text-align: justify !important;
            -webkit-hyphens: auto !important;
            hyphens: auto !important;
        }
        img {
            max-width: 100% !important;
            max-height: 90vh !important;
            height: auto !important;
            object-fit: contain !important;
            break-inside: avoid !important;
        }
        p {
            text-indent: 1.5em !important;
            margin: 0 0 0.3em 0 !important;
            orphans: 2 !important;
            widows: 2 !important;
        }
        p:first-child, h1 + p, h2 + p, h3 + p, h4 + p, hr + p, blockquote + p {
            text-indent: 0 !important;
        }
        h1, h2, h3, h4, h5, h6 {
            line-height: 1.3 !important;
            margin-top: 1.2em !important;
            margin-bottom: 0.4em !important;
            break-after: avoid !important;
            text-align: left !important;
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
            border-left: 3px solid \(fg) !important;
            opacity: 0.85 !important;
            margin: 0.8em 0 0.8em 0.5em !important;
            padding-left: 1em !important;
            break-inside: avoid !important;
        }
        pre, code {
            font-family: 'SF Mono', 'Menlo', monospace !important;
            font-size: 0.85em !important;
        }
        pre {
            overflow-x: auto !important;
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
        case .light: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .sepia: return Color(red: 0.56, green: 0.47, blue: 0.36)
        case .dark: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}
