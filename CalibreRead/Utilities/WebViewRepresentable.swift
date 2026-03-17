import SwiftUI
import WebKit

/// Controller that provides direct access to the WKWebView for page navigation.
/// Uses Readium-style progression-based navigation and scroll positioning.
@MainActor
@Observable
final class EPUBPageController {
    fileprivate weak var webView: WKWebView?
    /// Fraction to navigate to once the next chapter finishes loading.
    var pendingFraction: Double?

    func nextPage() {
        webView?.evaluateJavaScript("readium.scrollRight()", completionHandler: nil)
    }

    func previousPage() {
        webView?.evaluateJavaScript("readium.scrollLeft()", completionHandler: nil)
    }

    func goToFraction(_ fraction: Double) {
        webView?.evaluateJavaScript("readium.scrollToPosition(\(fraction))", completionHandler: nil)
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
        userController.add(context.coordinator, name: "readium")

        // Inject Readium CSS at document start via <style> tags in <head>
        // This ensures styles are applied before any rendering occurs
        let readiumCSSScript = WKUserScript(
            source: Self.readiumCSSInjectionJS(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(readiumCSSScript)

        // Hide body immediately on every navigation to prevent unstyled flash
        let hideScript = WKUserScript(
            source: """
            document.addEventListener('DOMContentLoaded', function() {
                document.body.style.opacity = '0';
                window.webkit.messageHandlers.readium.postMessage({ action: 'contentHidden' });
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

        controller.webView = webView

        let isNewChapter = context.coordinator.currentURL != fileURL

        if isNewChapter {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            loadContent(in: webView)
        } else if context.coordinator.theme != theme || context.coordinator.fontSize != fontSize {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            applyReadiumUserSettings(in: webView, theme: theme, fontSize: fontSize)
        }
    }

    private func loadContent(in webView: WKWebView) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: contentBaseURL)
    }

    /// Apply theme and font size via Readium CSS custom properties on :root style attribute
    private func applyReadiumUserSettings(in webView: WKWebView, theme: ReaderTheme, fontSize: Int) {
        let styleValue = theme.readiumRootStyle(fontSize: fontSize)
        let js = """
        (function() {
            document.documentElement.style.cssText = `\(styleValue)`;
            setTimeout(function() { readium.recalculate(); }, 100);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Generate the JavaScript that injects Readium CSS stylesheets into the document <head>.
    /// Uses inline styles loaded from the bundle at build time.
    private static func readiumCSSInjectionJS() -> String {
        let beforeCSS = loadCSSResource("ReadiumCSS-before")
        let defaultCSS = loadCSSResource("ReadiumCSS-default")
        let afterCSS = loadCSSResource("ReadiumCSS-after")

        return """
        (function() {
            function injectCSS(id, css, prepend) {
                var s = document.createElement('style');
                s.id = id;
                s.textContent = css;
                var head = document.head || document.documentElement;
                if (prepend && head.firstChild) {
                    head.insertBefore(s, head.firstChild);
                } else {
                    head.appendChild(s);
                }
            }

            // Inject before (base, fonts, safeguards) — prepend so it comes first
            injectCSS('readium-css-before', `\(beforeCSS)`, true);

            // Inject default (unstyled publication styles)
            injectCSS('readium-css-default', `\(defaultCSS)`, false);

            // Additional scrollbar/overflow hiding at document start
            var s = document.createElement('style');
            s.textContent = 'html { overflow: hidden !important; } ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }';
            (document.head || document.documentElement).appendChild(s);
        })();
        """
    }

    private static func loadCSSResource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "css", subdirectory: "readium-css"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback: try without subdirectory (flat bundle)
            guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return content.replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "\\", with: "\\\\")
        }
        return content.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
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

        /// Disable native scroll indicators on all NSScrollView instances inside
        /// the WKWebView's subview hierarchy.
        private var didDisableScrollers = false
        private func disableNativeScrollers(in view: NSView) {
            if let sv = view as? NSScrollView {
                sv.hasVerticalScroller = false
                sv.hasHorizontalScroller = false
                sv.scrollerStyle = .overlay
            }
            for child in view.subviews {
                disableNativeScrollers(in: child)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !didDisableScrollers {
                didDisableScrollers = true
                disableNativeScrollers(in: webView)
            }
            currentURL = webView.url

            // Inject Readium CSS after module (pagination, themes, user settings)
            let afterCSS = EPUBWebView.loadCSSResource("ReadiumCSS-after")
            let styleValue = theme.readiumRootStyle(fontSize: fontSize)

            let setupJS = """
            (function() {
                // Inject after CSS (pagination, themes, user settings)
                var afterStyle = document.getElementById('readium-css-after');
                if (!afterStyle) {
                    afterStyle = document.createElement('style');
                    afterStyle.id = 'readium-css-after';
                    document.head.appendChild(afterStyle);
                }
                afterStyle.textContent = `\(afterCSS)`;

                // Apply theme + user settings via :root style attribute (Readium convention)
                document.documentElement.style.cssText = `\(styleValue)`;

                // ========== Readium-style Pagination Engine ==========
                var readium = {
                    isReflowable: true,
                    currentPage: 0,
                    totalPages: 1,
                    pageWidth: 0,

                    // Recalculate column layout and page count
                    recalculate: function() {
                        var vw = window.innerWidth;
                        var vh = window.innerHeight;

                        // Readium uses CSS column layout on :root.
                        // The column gap is set to the viewport width so that each
                        // "page" is exactly one viewport wide.
                        var colGap = vw;
                        var colWidth = vw;

                        document.documentElement.style.setProperty('--RS__colWidth', colWidth + 'px');
                        document.documentElement.style.setProperty('--RS__colGap', colGap + 'px');
                        document.documentElement.style.setProperty('--RS__colCount', '1');

                        this.pageWidth = vw;

                        // Force layout reflow
                        document.documentElement.offsetHeight;

                        var scrollW = document.documentElement.scrollWidth;
                        this.totalPages = Math.max(1, Math.round(scrollW / this.pageWidth));

                        // Clamp current page
                        if (this.currentPage >= this.totalPages) {
                            this.currentPage = this.totalPages - 1;
                        }

                        this.applyScroll();
                        this.reportPage();
                    },

                    // Readium-style: set scroll position on the document element
                    applyScroll: function() {
                        document.documentElement.scrollLeft = this.currentPage * this.pageWidth;
                    },

                    reportPage: function() {
                        window.webkit.messageHandlers.readium.postMessage({
                            current: this.currentPage + 1,
                            total: this.totalPages
                        });
                    },

                    goToPage: function(n) {
                        this.currentPage = Math.max(0, Math.min(n, this.totalPages - 1));
                        this.applyScroll();
                        this.reportPage();
                    },

                    // Readium-style: scroll right = next page
                    scrollRight: function() {
                        if (document.body.style.opacity === '0') return;
                        if (this.currentPage < this.totalPages - 1) {
                            this.goToPage(this.currentPage + 1);
                        } else {
                            window.webkit.messageHandlers.readium.postMessage({ action: 'nextChapter' });
                        }
                    },

                    // Readium-style: scroll left = previous page
                    scrollLeft: function() {
                        if (document.body.style.opacity === '0') return;
                        if (this.currentPage > 0) {
                            this.goToPage(this.currentPage - 1);
                        } else {
                            window.webkit.messageHandlers.readium.postMessage({ action: 'prevChapter' });
                        }
                    },

                    // Readium-style: navigate to a position (0.0 to 1.0 progression)
                    scrollToPosition: function(position) {
                        var page = Math.round(position * Math.max(0, this.totalPages - 1));
                        this.goToPage(page);
                    },

                    // Get current progression as fraction 0.0 to 1.0
                    getProgression: function() {
                        if (this.totalPages <= 1) return 0;
                        return this.currentPage / (this.totalPages - 1);
                    },

                    // Readium-style: scroll to element by ID
                    scrollToId: function(id) {
                        var el = document.getElementById(id);
                        if (el) {
                            var rect = el.getBoundingClientRect();
                            var page = Math.floor((document.documentElement.scrollLeft + rect.left) / this.pageWidth);
                            this.goToPage(page);
                        }
                    },

                    // Readium-style: snap offset to page boundary
                    snapOffset: function(offset) {
                        return Math.round(offset / this.pageWidth) * this.pageWidth;
                    },

                    // Readium-style: get column count per screen
                    getColumnCountPerScreen: function() {
                        return parseInt(getComputedStyle(document.documentElement).getPropertyValue('column-count')) || 1;
                    },

                    // Readium-style: set CSS property on :root
                    setCSSProperties: function(properties) {
                        for (var key in properties) {
                            if (properties.hasOwnProperty(key)) {
                                document.documentElement.style.setProperty(key, properties[key]);
                            }
                        }
                        this.recalculate();
                    },

                    // Readium-style: find first visible locator (simplified)
                    findFirstVisibleLocator: function() {
                        return {
                            progression: this.getProgression(),
                            totalPages: this.totalPages,
                            currentPage: this.currentPage + 1
                        };
                    }
                };

                window.readium = readium;

                // Backward compat alias
                window.CalibreReader = {
                    nextPage: function() { readium.scrollRight(); },
                    prevPage: function() { readium.scrollLeft(); },
                    goToFraction: function(f) { readium.scrollToPosition(f); },
                    getFraction: function() { return readium.getProgression(); },
                    recalculate: function() { readium.recalculate(); }
                };

                // Initial calculation after layout settles, then reveal
                setTimeout(function() {
                    readium.recalculate();
                    if (!window._readiumWaitForFraction) {
                        document.body.style.opacity = '1';
                        window.webkit.messageHandlers.readium.postMessage({ action: 'contentReady' });
                    }
                }, 200);

                // Second recalculation for images that load late
                setTimeout(function() { readium.recalculate(); }, 800);

                // Recalculate on resize — hide content while layout settles
                var resizeTimer = null;
                window.addEventListener('resize', function() {
                    document.body.style.opacity = '0';
                    window.webkit.messageHandlers.readium.postMessage({ action: 'contentHidden' });
                    clearTimeout(resizeTimer);
                    resizeTimer = setTimeout(function() {
                        readium.recalculate();
                        document.body.style.opacity = '1';
                        window.webkit.messageHandlers.readium.postMessage({ action: 'contentReady' });
                    }, 150);
                });

                // Recalculate when images finish loading
                document.querySelectorAll('img').forEach(function(img) {
                    if (!img.complete) {
                        img.addEventListener('load', function() {
                            readium.recalculate();
                        });
                    }
                });

                // Keyboard navigation (Readium-style)
                document.addEventListener('keydown', function(e) {
                    if (document.body.style.opacity === '0') return;
                    if (e.key === 'ArrowRight' || e.key === ' ') {
                        e.preventDefault();
                        readium.scrollRight();
                    } else if (e.key === 'ArrowLeft') {
                        e.preventDefault();
                        readium.scrollLeft();
                    }
                });

                // Prevent native scrolling
                document.addEventListener('wheel', function(e) { e.preventDefault(); }, { passive: false });
                document.addEventListener('scroll', function(e) {
                    // Allow our programmatic scrolls but prevent user scrolling
                    var expected = readium.currentPage * readium.pageWidth;
                    if (Math.abs(document.documentElement.scrollLeft - expected) > 2) {
                        document.documentElement.scrollLeft = expected;
                    }
                });
            })();
            """
            webView.evaluateJavaScript(setupJS, completionHandler: nil)

            // Apply pending fraction (e.g., go to last page when navigating backward)
            if let fraction = controller?.pendingFraction {
                controller?.pendingFraction = nil
                let flagJS = "window._readiumWaitForFraction = true;"
                webView.evaluateJavaScript(flagJS, completionHandler: nil)
                let goToJS = """
                setTimeout(function() {
                    readium.scrollToPosition(\(fraction));
                    document.body.style.opacity = '1';
                    window.webkit.messageHandlers.readium.postMessage({ action: 'contentReady' });
                }, 250);
                """
                webView.evaluateJavaScript(goToJS, completionHandler: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "readium", let dict = message.body as? [String: Any] {
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

// MARK: - Reader Theme (Readium CSS-based)

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

    /// Generate the :root style attribute value using Readium CSS conventions.
    /// Readium activates themes via style attributes like "readium-night-on" on :root.
    /// User settings use --USER__* CSS custom properties.
    func readiumRootStyle(fontSize: Int) -> String {
        var parts: [String] = []

        // Theme activation (Readium convention)
        switch self {
        case .light:
            break // Default — no special attribute needed
        case .sepia:
            parts.append("readium-sepia-on: yes")
        case .dark:
            parts.append("readium-night-on: yes")
        }

        // User font size via Readium CSS custom property
        parts.append("--USER__fontSize: \(fontSize)px")

        // User text settings
        parts.append("--USER__textAlign: justify")
        parts.append("--USER__bodyHyphens: auto")

        return parts.joined(separator: "; ")
    }

    // MARK: - SwiftUI Colors (matching Readium CSS theme values)

    var swiftUIBackground: Color {
        switch self {
        case .light: return Color(red: 1, green: 1, blue: 1)
        case .sepia: return Color(red: 0.98, green: 0.957, blue: 0.91)
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.118)
        }
    }

    var swiftUIForeground: Color {
        switch self {
        case .light: return Color(red: 0.071, green: 0.071, blue: 0.071)
        case .sepia: return Color(red: 0.071, green: 0.071, blue: 0.071)
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
