import SwiftUI
import WebKit

/// Controller that provides direct access to the WKWebView for page navigation.
/// Arrow buttons and key handlers call methods here, which execute JS immediately
/// on the webview — bypassing the error-prone updateNSView/pageCommand path.
@MainActor
@Observable
final class EPUBPageController {
    fileprivate weak var webView: WKWebView?
    /// Fraction to navigate to once the next chapter finishes loading.
    var pendingFraction: Double?

    func nextPage() {
        webView?.evaluateJavaScript("CalibreReader.nextPage()", completionHandler: nil)
    }

    func previousPage() {
        webView?.evaluateJavaScript("CalibreReader.prevPage()", completionHandler: nil)
    }

    func goToFraction(_ fraction: Double) {
        webView?.evaluateJavaScript("CalibreReader.goToFraction(\(fraction))", completionHandler: nil)
    }
}

struct EPUBWebView: NSViewRepresentable {
    let fileURL: URL
    let contentBaseURL: URL
    let theme: ReaderTheme
    let fontSize: Int
    let controller: EPUBPageController
    let onPageInfo: ((Int, Int) -> Void)?  // (currentPage, totalPages)
    let onChapterEnd: ((ChapterEdge) -> Void)?
    let onContentReadyChanged: ((Bool) -> Void)?

    enum ChapterEdge {
        case next
        case previous
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageInfo: onPageInfo, onChapterEnd: onChapterEnd, onContentReadyChanged: onContentReadyChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "pageHandler")

        // Hide body immediately on every navigation to prevent unstyled flash
        let hideScript = WKUserScript(
            source: """
            document.addEventListener('DOMContentLoaded', function() {
                document.body.style.opacity = '0';
                window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentHidden' });
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(hideScript)

        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.controller = controller
        context.coordinator.theme = theme
        context.coordinator.fontSize = fontSize
        context.coordinator.contentBaseURL = contentBaseURL

        // Wire up the controller so arrow buttons can call JS directly
        controller.webView = webView

        loadContent(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPageInfo = onPageInfo
        context.coordinator.onChapterEnd = onChapterEnd
        context.coordinator.onContentReadyChanged = onContentReadyChanged
        context.coordinator.contentBaseURL = contentBaseURL
        context.coordinator.controller = controller

        // Keep controller's webView reference current
        controller.webView = webView

        let isNewChapter = context.coordinator.currentURL != fileURL

        if isNewChapter {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            loadContent(in: webView)
        } else if context.coordinator.theme != theme || context.coordinator.fontSize != fontSize {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            injectStyles(in: webView)
        }
    }

    private func loadContent(in webView: WKWebView) {
        // Grant read access to the entire EPUB content directory so images,
        // stylesheets, and other resources from sibling directories load.
        webView.loadFileURL(fileURL, allowingReadAccessTo: contentBaseURL)
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
            setTimeout(function() { CalibreReader.recalculate(); }, 100);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var currentURL: URL?
        var contentBaseURL: URL?
        var controller: EPUBPageController?
        var onPageInfo: ((Int, Int) -> Void)?
        var onChapterEnd: ((ChapterEdge) -> Void)?
        var onContentReadyChanged: ((Bool) -> Void)?
        var theme: ReaderTheme = .light
        var fontSize: Int = 18

        init(onPageInfo: ((Int, Int) -> Void)?, onChapterEnd: ((ChapterEdge) -> Void)?, onContentReadyChanged: ((Bool) -> Void)?) {
            self.onPageInfo = onPageInfo
            self.onChapterEnd = onChapterEnd
            self.onContentReadyChanged = onContentReadyChanged
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

                var CalibreReader = {
                    currentPage: 0,
                    totalPages: 1,
                    pageWidth: 0,

                    recalculate: function() {
                        var vw = window.innerWidth;
                        var vh = window.innerHeight;
                        var maxContentWidth = 720;
                        var paddingH = Math.max(60, (vw - maxContentWidth) / 2);
                        var paddingV = 40;
                        var gap = paddingH * 2;
                        var colWidth = vw - gap;

                        // Apply column dimensions dynamically
                        document.body.style.columnWidth = colWidth + 'px';
                        document.body.style.columnGap = gap + 'px';
                        document.body.style.height = vh + 'px';
                        document.body.style.padding = paddingV + 'px ' + paddingH + 'px';

                        this.pageWidth = vw;

                        // Force layout reflow before measuring
                        document.body.offsetHeight;

                        var scrollW = document.body.scrollWidth;
                        this.totalPages = Math.max(1, Math.round(scrollW / this.pageWidth));

                        // Clamp current page
                        if (this.currentPage >= this.totalPages) {
                            this.currentPage = this.totalPages - 1;
                        }

                        this.applyTransform();
                        this.reportPage();
                    },

                    applyTransform: function() {
                        document.body.style.transform = 'translateX(-' + (this.currentPage * this.pageWidth) + 'px)';
                    },

                    reportPage: function() {
                        window.webkit.messageHandlers.pageHandler.postMessage({
                            current: this.currentPage + 1,
                            total: this.totalPages
                        });
                    },

                    goToPage: function(n) {
                        this.currentPage = Math.max(0, Math.min(n, this.totalPages - 1));
                        this.applyTransform();
                        this.reportPage();
                    },

                    nextPage: function() {
                        if (document.body.style.opacity === '0') return;
                        if (this.currentPage < this.totalPages - 1) {
                            this.goToPage(this.currentPage + 1);
                        } else {
                            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'nextChapter' });
                        }
                    },

                    prevPage: function() {
                        if (document.body.style.opacity === '0') return;
                        if (this.currentPage > 0) {
                            this.goToPage(this.currentPage - 1);
                        } else {
                            window.webkit.messageHandlers.pageHandler.postMessage({ action: 'prevChapter' });
                        }
                    },

                    goToFraction: function(f) {
                        var page = Math.round(f * Math.max(0, this.totalPages - 1));
                        this.goToPage(page);
                    },

                    getFraction: function() {
                        if (this.totalPages <= 1) return 0;
                        return this.currentPage / (this.totalPages - 1);
                    }
                };

                window.CalibreReader = CalibreReader;

                // Initial calculation after layout settles, then reveal
                // Body stays hidden until explicitly revealed to avoid flash
                // when navigating backward (goToFraction needs to run first)
                setTimeout(function() {
                    CalibreReader.recalculate();
                    if (!window._CalibreWaitForFraction) {
                        document.body.style.opacity = '1';
                        window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
                    }
                }, 200);
                // Second recalculation for images that load late
                setTimeout(function() { CalibreReader.recalculate(); }, 800);

                // Recalculate on resize — hide content while layout settles
                var resizeTimer = null;
                window.addEventListener('resize', function() {
                    document.body.style.opacity = '0';
                    window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentHidden' });
                    clearTimeout(resizeTimer);
                    resizeTimer = setTimeout(function() {
                        CalibreReader.recalculate();
                        document.body.style.opacity = '1';
                        window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
                    }, 150);
                });

                // Recalculate when images finish loading
                document.querySelectorAll('img').forEach(function(img) {
                    if (!img.complete) {
                        img.addEventListener('load', function() {
                            CalibreReader.recalculate();
                        });
                    }
                });

                // Handle keyboard navigation within the webview
                document.addEventListener('keydown', function(e) {
                    if (document.body.style.opacity === '0') return;
                    if (e.key === 'ArrowRight' || e.key === ' ') {
                        e.preventDefault();
                        CalibreReader.nextPage();
                    } else if (e.key === 'ArrowLeft') {
                        e.preventDefault();
                        CalibreReader.prevPage();
                    }
                });

                // Prevent native scrolling (both wheel and trackpad)
                document.addEventListener('wheel', function(e) { e.preventDefault(); }, { passive: false });
                document.addEventListener('scroll', function(e) {
                    window.scrollTo(0, 0);
                    document.documentElement.scrollLeft = 0;
                });
            })();
            """
            webView.evaluateJavaScript(setupJS, completionHandler: nil)

            // Apply pending fraction (e.g., go to last page when navigating backward)
            if let fraction = controller?.pendingFraction {
                controller?.pendingFraction = nil
                // Set flag BEFORE setup JS runs so the reveal is deferred
                let flagJS = "window._CalibreWaitForFraction = true;"
                webView.evaluateJavaScript(flagJS, completionHandler: nil)
                let goToJS = """
                setTimeout(function() {
                    CalibreReader.goToFraction(\(fraction));
                    document.body.style.opacity = '1';
                    window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
                }, 250);
                """
                webView.evaluateJavaScript(goToJS, completionHandler: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pageHandler", let dict = message.body as? [String: Any] {
                if let current = dict["current"] as? Int, let total = dict["total"] as? Int {
                    onPageInfo?(current, total)
                }
                if let action = dict["action"] as? String {
                    if action == "nextChapter" {
                        onChapterEnd?(.next)
                    } else if action == "prevChapter" {
                        onChapterEnd?(.previous)
                    } else if action == "contentHidden" {
                        onContentReadyChanged?(false)
                    } else if action == "contentReady" {
                        onContentReadyChanged?(true)
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
            line-height: 1.5 !important;
            letter-spacing: 0.01em !important;
            word-spacing: 0.05em !important;
            text-rendering: optimizeLegibility !important;
            -webkit-font-smoothing: antialiased !important;
            background-color: \(bg) !important;
            color: \(fg) !important;
            margin: 0 !important;
            box-sizing: border-box !important;
            column-fill: auto !important;
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
            break-inside: avoid !important;
        }
        p {
            text-indent: 1.5em !important;
            margin: 0 0 0.3em 0 !important;
            orphans: 2 !important;
            widows: 2 !important;
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
        case .light: return Color(red: 0.35, green: 0.35, blue: 0.37)
        case .sepia: return Color(red: 0.40, green: 0.33, blue: 0.24)
        case .dark: return Color(red: 0.56, green: 0.56, blue: 0.58)
        }
    }
}
