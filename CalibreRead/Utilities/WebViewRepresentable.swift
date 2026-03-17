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
    let onWritingModeDetected: ((Bool) -> Void)?  // true = vertical-rl

    enum ChapterEdge {
        case next
        case previous
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageInfo: onPageInfo, onChapterEnd: onChapterEnd, onContentReadyChanged: onContentReadyChanged, onWritingModeDetected: onWritingModeDetected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "pageHandler")

        // Inject scrollbar-hiding CSS at document start — before any rendering
        // occurs — so native/WebKit scrollbars never flash during navigation.
        let earlyStyleScript = WKUserScript(
            source: """
            (function() {
                var s = document.createElement('style');
                s.textContent = 'html { overflow: hidden !important; } ::-webkit-scrollbar { display: none !important; width: 0 !important; height: 0 !important; }';
                (document.head || document.documentElement).appendChild(s);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(earlyStyleScript)

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
        context.coordinator.onWritingModeDetected = onWritingModeDetected
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
            requestAnimationFrame(function() { CalibreReader.recalculate(); });
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Loads the reader.js bundle from the app's Resources directory.
    private static let readerJS: String = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("reader.js not found in bundle — ensure it is included in the Resources build phase")
        }
        return source
    }()

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var currentURL: URL?
        var contentBaseURL: URL?
        var controller: EPUBPageController?
        var onPageInfo: ((Int, Int) -> Void)?
        var onChapterEnd: ((ChapterEdge) -> Void)?
        var onContentReadyChanged: ((Bool) -> Void)?
        var onWritingModeDetected: ((Bool) -> Void)?
        var theme: ReaderTheme = .light
        var fontSize: Int = 18

        init(onPageInfo: ((Int, Int) -> Void)?, onChapterEnd: ((ChapterEdge) -> Void)?, onContentReadyChanged: ((Bool) -> Void)?, onWritingModeDetected: ((Bool) -> Void)?) {
            self.onPageInfo = onPageInfo
            self.onChapterEnd = onChapterEnd
            self.onContentReadyChanged = onContentReadyChanged
            self.onWritingModeDetected = onWritingModeDetected
        }

        /// Disable native scroll indicators on all NSScrollView instances inside
        /// the WKWebView's subview hierarchy. Called once after first navigation.
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

            // Inject theme CSS, then the pagination engine from reader.js
            let css = theme.css(fontSize: fontSize)
            let cssInjection = """
            (function() {
                var style = document.getElementById('calibreread-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'calibreread-style';
                    document.head.appendChild(style);
                }
                style.textContent = `\(css)`;
            })();
            """
            webView.evaluateJavaScript(cssInjection, completionHandler: nil)
            webView.evaluateJavaScript(EPUBWebView.readerJS, completionHandler: nil)

            // Apply pending fraction (e.g., go to last page when navigating backward)
            if let fraction = controller?.pendingFraction {
                controller?.pendingFraction = nil
                // Set flag BEFORE setup JS runs so the reveal is deferred
                let flagJS = "window._CalibreWaitForFraction = true;"
                webView.evaluateJavaScript(flagJS, completionHandler: nil)
                let goToJS = """
                requestAnimationFrame(function() {
                    CalibreReader.goToFraction(\(fraction));
                    document.body.style.opacity = '1';
                    window.webkit.messageHandlers.pageHandler.postMessage({ action: 'contentReady' });
                });
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
                    } else if action == "writingMode" {
                        let isVertical = dict["isVertical"] as? Bool ?? false
                        onWritingModeDetected?(isVertical)
                    }
                }
            }
        }
    }
}
