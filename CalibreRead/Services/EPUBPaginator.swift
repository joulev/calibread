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
    /// Invisible window that hosts the WKWebView — required for WKWebView to
    /// actually load content and fire navigation delegate callbacks.
    private let hostWindow: NSWindow
    private let chapters: [EPUBService.Chapter]
    private let contentBaseURL: URL
    private let theme: ReaderTheme
    private let fontSize: Int
    private var currentIndex = 0

    private var navigationContinuation: CheckedContinuation<Void, Never>?
    /// Set to true when a navigation delegate callback fires before we enter the continuation.
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
        config.userContentController = WKUserContentController()

        let wv = WKWebView(frame: NSRect(origin: .zero, size: viewportSize), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")

        // WKWebView needs to be hosted in a real window for navigation delegate
        // callbacks to fire and for CSS column layout to be computed. We make the
        // window fully transparent and behind everything so it's invisible.
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
        print("[EPUBPaginator] init: \(chapters.count) chapters, viewport=\(viewportSize.width)x\(viewportSize.height), fontSize=\(fontSize), theme=\(theme), contentBaseURL=\(contentBaseURL.path)")
    }

    deinit {
        hostWindow.orderOut(nil)
    }

    /// Measure the next chapter's page count. Returns `nil` when all chapters have been measured.
    func measureNext() async -> (index: Int, pageCount: Int)? {
        guard currentIndex < chapters.count else {
            print("[EPUBPaginator] measureNext: all \(chapters.count) chapters done")
            return nil
        }

        let chapter = chapters[currentIndex]
        let index = currentIndex
        currentIndex += 1

        let fileExists = FileManager.default.fileExists(atPath: chapter.fileURL.path)
        print("[EPUBPaginator] measureNext[\(index)]: loading \(chapter.fileURL.lastPathComponent) (exists: \(fileExists))")

        // Load the file first, then await the navigation delegate callback.
        // Both must happen on the main actor. We use a flag to handle the case
        // where didFinish fires before we enter the continuation.
        navigationDidComplete = false
        navigationContinuation = nil

        webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)

        // If the delegate already fired (set navigationDidComplete before we
        // get here), skip the await. Otherwise wait for the callback.
        if navigationDidComplete {
            print("[EPUBPaginator] measureNext[\(index)]: navigation completed synchronously")
            navigationDidComplete = false
        } else {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.navigationContinuation = cont
            }
        }

        print("[EPUBPaginator] measureNext[\(index)]: navigation finished, measuring pages...")

        // Brief delay for images to affect layout
        try? await Task.sleep(for: .milliseconds(150))

        let pageCount = await measurePages()
        print("[EPUBPaginator] measureNext[\(index)]: pageCount = \(pageCount)")
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
            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    print("[EPUBPaginator] measurePages JS error: \(error.localizedDescription)")
                }
                let pages = (result as? Int) ?? 1
                print("[EPUBPaginator] measurePages JS result: raw=\(String(describing: result)), pages=\(pages), vw=\(vw), vh=\(vh)")
                cont.resume(returning: pages)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        print("[EPUBPaginator] didFinish: continuation=\(navigationContinuation != nil ? "set" : "nil")")
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }

    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[EPUBPaginator] didFail: \(error.localizedDescription), continuation=\(navigationContinuation != nil ? "set" : "nil")")
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }

    func webView(_ wv: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[EPUBPaginator] didFailProvisionalNavigation: \(error.localizedDescription), continuation=\(navigationContinuation != nil ? "set" : "nil")")
        if let cont = navigationContinuation {
            navigationContinuation = nil
            cont.resume()
        } else {
            navigationDidComplete = true
        }
    }
}
