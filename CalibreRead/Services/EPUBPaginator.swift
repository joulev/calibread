import WebKit

/// Measures page counts for all chapters in an EPUB by loading each into a hidden
/// WKWebView with the same Readium CSS column-based pagination layout as the reader.
///
/// After pagination completes, the caller knows:
/// - Total pages in the entire book
/// - Pages per section/chapter
/// - Current global page position (derived from chapter index + page within chapter)
@MainActor
final class EPUBPaginator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    /// Invisible window that hosts the WKWebView — required for WKWebView to
    /// actually load content and fire navigation delegate callbacks.
    private let hostWindow: NSWindow
    private let chapters: [EPUBService.Chapter]
    private let contentBaseURL: URL
    private let theme: ReaderTheme
    private let fontSize: Int
    private var currentIndex = 0

    private var navigationContinuation: CheckedContinuation<Void, Never>?
    private var navigationDidComplete = false

    init(
        chapters: [EPUBService.Chapter],
        contentBaseURL: URL,
        theme: ReaderTheme,
        fontSize: Int,
        viewportSize: CGSize
    ) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let userController = WKUserContentController()

        // Inject Readium CSS at document start (same as reader)
        let readiumCSSScript = WKUserScript(
            source: EPUBPaginator.readiumCSSInjectionJS(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userController.addUserScript(readiumCSSScript)
        config.userContentController = userController

        let wv = WKWebView(frame: NSRect(origin: .zero, size: viewportSize), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")

        // WKWebView needs to be hosted in a real window for navigation delegate
        // callbacks to fire and for CSS column layout to be computed.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.contentView = wv
        window.orderFrontRegardless()

        self.webView = wv
        self.hostWindow = window
        self.chapters = chapters
        self.contentBaseURL = contentBaseURL
        self.theme = theme
        self.fontSize = fontSize

        super.init()
        webView.navigationDelegate = self
    }

    deinit {
        hostWindow.orderOut(nil)
    }

    /// Measure the next chapter's page count. Returns `nil` when all chapters have been measured.
    func measureNext() async -> (index: Int, pageCount: Int)? {
        guard currentIndex < chapters.count else { return nil }

        let chapter = chapters[currentIndex]
        let index = currentIndex
        currentIndex += 1

        navigationDidComplete = false
        navigationContinuation = nil

        webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)

        if navigationDidComplete {
            navigationDidComplete = false
        } else {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.navigationContinuation = cont
            }
        }

        // Brief delay for images to affect layout
        try? await Task.sleep(for: .milliseconds(150))

        let pageCount = await measurePages()
        return (index: index, pageCount: pageCount)
    }

    // MARK: - Page Measurement (Readium CSS approach)

    private func measurePages() async -> Int {
        let styleValue = theme.readiumRootStyle(fontSize: fontSize)
        let afterCSS = EPUBWebView.loadCSSResource("ReadiumCSS-after")
        let vw = Int(webView.frame.width)

        let js = """
        (function() {
            // Inject Readium CSS after module
            var afterStyle = document.getElementById('readium-css-after');
            if (!afterStyle) {
                afterStyle = document.createElement('style');
                afterStyle.id = 'readium-css-after';
                document.head.appendChild(afterStyle);
            }
            afterStyle.textContent = `\(afterCSS)`;

            // Apply theme + user settings (Readium convention: style on :root)
            document.documentElement.style.cssText = `\(styleValue)`;

            // Set Readium CSS column variables for single-column pagination
            var vw = \(vw);
            document.documentElement.style.setProperty('--RS__colWidth', vw + 'px');
            document.documentElement.style.setProperty('--RS__colGap', vw + 'px');
            document.documentElement.style.setProperty('--RS__colCount', '1');

            // Force layout reflow
            document.documentElement.offsetHeight;

            var scrollW = document.documentElement.scrollWidth;
            return Math.max(1, Math.round(scrollW / vw));
        })();
        """

        return await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? Int) ?? 1)
            }
        }
    }

    // MARK: - Readium CSS Injection (same as reader for consistent measurement)

    private static func readiumCSSInjectionJS() -> String {
        let beforeCSS = loadCSSResource("ReadiumCSS-before")
        let defaultCSS = loadCSSResource("ReadiumCSS-default")

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
            injectCSS('readium-css-before', `\(beforeCSS)`, true);
            injectCSS('readium-css-default', `\(defaultCSS)`, false);
        })();
        """
    }

    private static func loadCSSResource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "css", subdirectory: "readium-css"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return content.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
        }
        return content.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }

    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }
}
