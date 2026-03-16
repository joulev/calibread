import WebKit

/// Measures page counts for all chapters in an EPUB by loading each into a hidden
/// WKWebView with the same column-based pagination layout as the reader.
///
/// After pagination completes, the caller knows:
/// - Total pages in the entire book
/// - Pages per section/chapter
/// - Current global page position (derived from chapter index + page within chapter)
@MainActor
final class EPUBPaginator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    /// Offscreen window that hosts the WKWebView — required for navigation
    /// delegate callbacks to fire and for JS layout to work correctly.
    private let hostWindow: NSWindow
    private let chapters: [EPUBService.Chapter]
    private let contentBaseURL: URL
    private let theme: ReaderTheme
    private let fontSize: Int
    private var currentIndex = 0

    private var navigationContinuation: CheckedContinuation<Void, Never>?

    init(
        chapters: [EPUBService.Chapter],
        contentBaseURL: URL,
        theme: ReaderTheme,
        fontSize: Int,
        viewportSize: CGSize
    ) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController = WKUserContentController()

        let wv = WKWebView(frame: NSRect(origin: .zero, size: viewportSize), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")

        // Host the WKWebView in an offscreen window so that navigation
        // delegate callbacks fire and CSS column layout is computed correctly.
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: viewportSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = wv
        window.orderBack(nil)

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

        webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.navigationContinuation = cont
        }

        // Brief delay for images to affect layout
        try? await Task.sleep(for: .milliseconds(150))

        let pageCount = await measurePages()
        return (index: index, pageCount: pageCount)
    }

    // MARK: - Page Measurement

    private func measurePages() async -> Int {
        let css = theme.css(fontSize: fontSize)
        let vw = Int(webView.frame.width)
        let vh = Int(webView.frame.height)

        let js = """
        (function() {
            var style = document.getElementById('calibreread-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'calibreread-style';
                document.head.appendChild(style);
            }
            style.textContent = `\(css)`;

            var vw = \(vw);
            var vh = \(vh);
            var maxContentWidth = 720;
            var paddingH = Math.max(60, (vw - maxContentWidth) / 2);
            var paddingV = 40;
            var gap = paddingH * 2;
            var colWidth = vw - gap;

            document.body.style.columnWidth = colWidth + 'px';
            document.body.style.columnGap = gap + 'px';
            document.body.style.height = vh + 'px';
            document.body.style.padding = paddingV + 'px ' + paddingH + 'px';
            document.body.style.columnFill = 'auto';

            // Force layout reflow
            document.body.offsetHeight;

            var scrollW = document.body.scrollWidth;
            return Math.max(1, Math.round(scrollW / vw));
        })();
        """

        return await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? Int) ?? 1)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }
}
