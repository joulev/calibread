import WebKit

/// Measures page counts for all chapters in an EPUB using a pool of concurrent
/// WKWebViews. Chapters are processed in batches — all workers in a batch start
/// loading simultaneously (WKWebView renders internally on background threads),
/// then results are collected. This gives ~Nx speedup where N is the pool size.
///
/// Results are cached to disk so re-opening a book with the same settings is instant.
@MainActor
final class EPUBPaginator {
    private let chapters: [EPUBService.Chapter]
    private let contentBaseURL: URL
    private let theme: ReaderTheme
    private let fontSize: Int
    private let viewportSize: CGSize
    private let cacheKey: String

    /// Number of concurrent WKWebView workers.
    private static let concurrency = 4

    init(
        chapters: [EPUBService.Chapter],
        contentBaseURL: URL,
        theme: ReaderTheme,
        fontSize: Int,
        viewportSize: CGSize,
        bookIdentifier: String = ""
    ) {
        self.chapters = chapters
        self.contentBaseURL = contentBaseURL
        self.theme = theme
        self.fontSize = fontSize
        self.viewportSize = viewportSize

        // Build a cache key from all parameters that affect pagination
        let keyComponents = [
            bookIdentifier,
            "\(Int(viewportSize.width))x\(Int(viewportSize.height))",
            "\(fontSize)",
            theme.rawValue,
            "\(chapters.count)"
        ]
        self.cacheKey = keyComponents.joined(separator: "-")
    }

    // MARK: - Public API

    /// Measure all chapters and report progress via the callback.
    /// Returns the full array of page counts, or nil if cancelled.
    func measureAll(
        onProgress: @escaping (Int) -> Void
    ) async -> [Int]? {
        // Check cache first
        if let cached = PaginationCache.shared.load(key: cacheKey, chapterCount: chapters.count) {
            for i in 0..<cached.count {
                onProgress(i + 1)
            }
            return cached
        }

        guard !chapters.isEmpty else { return [] }

        let workerCount = min(Self.concurrency, chapters.count)
        let workers = (0..<workerCount).map { _ in
            PaginationWorker(
                contentBaseURL: contentBaseURL,
                theme: theme,
                fontSize: fontSize,
                viewportSize: viewportSize
            )
        }

        var results = [Int](repeating: 1, count: chapters.count)
        var completedCount = 0

        // Process chapters in batches. Within each batch, all workers start
        // loading simultaneously — WKWebView performs HTML parsing and layout
        // on internal background threads, so the loads genuinely overlap.
        for batchStart in stride(from: 0, to: chapters.count, by: workerCount) {
            guard !Task.isCancelled else { break }

            let batchEnd = min(batchStart + workerCount, chapters.count)
            let batchSize = batchEnd - batchStart

            // Phase 1: Kick off all loads in this batch (non-blocking)
            for i in 0..<batchSize {
                workers[i].startLoad(chapter: chapters[batchStart + i])
            }

            // Phase 2: Await navigation completion + measure each worker
            for i in 0..<batchSize {
                guard !Task.isCancelled else { break }
                let count = await workers[i].awaitMeasurement()
                results[batchStart + i] = count
                completedCount += 1
                onProgress(completedCount)
            }
        }

        // Tear down workers
        for worker in workers { worker.teardown() }

        guard !Task.isCancelled else { return nil }

        // Cache results
        PaginationCache.shared.save(key: cacheKey, counts: results)

        return results
    }
}

// MARK: - Pagination Worker

/// A single WKWebView-based worker with a split load/measure API.
/// `startLoad` kicks off navigation (non-blocking), and `awaitMeasurement`
/// waits for completion then measures the page count.
@MainActor
private final class PaginationWorker: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let hostWindow: NSWindow
    private let contentBaseURL: URL
    private let theme: ReaderTheme
    private let fontSize: Int

    private var navigationContinuation: CheckedContinuation<Void, Never>?
    private var navigationDidComplete = false

    init(
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

        // WKWebView needs a hosting window for navigation callbacks and CSS
        // column layout to work. Fully transparent and behind everything.
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
        self.contentBaseURL = contentBaseURL
        self.theme = theme
        self.fontSize = fontSize

        super.init()
        webView.navigationDelegate = self
    }

    func teardown() {
        hostWindow.orderOut(nil)
    }

    /// Start loading a chapter. This returns immediately — the actual loading
    /// happens asynchronously inside WKWebView's internal threads.
    func startLoad(chapter: EPUBService.Chapter) {
        navigationDidComplete = false
        navigationContinuation = nil
        webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: contentBaseURL)
    }

    /// Wait for the current load to finish, then wait for images/fonts and
    /// measure the page count.
    func awaitMeasurement() async -> Int {
        // Wait for navigation to complete
        if !navigationDidComplete {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.navigationContinuation = cont
            }
        }
        navigationDidComplete = false

        // Wait for all images and fonts, then measure
        return await measurePages()
    }

    /// Wait for images/fonts via callAsyncJavaScript (handles JS Promises natively),
    /// then measure page count using CSS column layout.
    private func measurePages() async -> Int {
        let css = theme.css(fontSize: fontSize)
        let vw = Int(webView.frame.width)
        let vh = Int(webView.frame.height)

        // Step 1: Wait for all images and fonts to finish loading.
        // callAsyncJavaScript natively awaits the returned Promise.
        let waitJS = """
            var images = Array.from(document.querySelectorAll('img'));
            var imagePromises = images.map(function(img) {
                if (img.complete) return Promise.resolve();
                return new Promise(function(resolve) {
                    img.addEventListener('load', resolve, { once: true });
                    img.addEventListener('error', resolve, { once: true });
                });
            });
            var fontReady = document.fonts ? document.fonts.ready : Promise.resolve();
            await Promise.all([fontReady].concat(imagePromises));
            return true;
        """

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            webView.callAsyncJavaScript(waitJS, arguments: [:], in: nil, in: .page) { _ in
                cont.resume()
            }
        }

        // Step 2: Apply styles and measure column layout
        let measureJS = """
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
            var maxContentWidth = 640;
            var paddingH = Math.max(60, (vw - maxContentWidth) / 2);
            var paddingV = 40;
            var gap = paddingH * 2;
            var colWidth = vw - gap;

            // Detect vertical writing mode
            var bodyWM = window.getComputedStyle(document.body).writingMode || '';
            var htmlWM = window.getComputedStyle(document.documentElement).writingMode || '';
            var wm = bodyWM || htmlWM || 'horizontal-tb';
            var isVertical = (wm === 'vertical-rl' || wm === 'vertical-lr' || wm === 'tb-rl' || wm === 'tb');

            // In vertical-rl, snap column width to a multiple of the actual
            // rendered line pitch.  A probe with <ruby> is used so furigana
            // annotations are accounted for (they widen lines beyond what CSS
            // line-height reports).
            if (isVertical) {
                var probe = document.createElement('div');
                probe.style.cssText = 'position:absolute;visibility:hidden;display:inline-block;';
                probe.innerHTML = '<ruby>字<rt>じ</rt></ruby>';
                document.body.appendChild(probe);
                var linePitch = probe.offsetWidth;
                document.body.removeChild(probe);
                if (linePitch > 0) {
                    var snapped = Math.floor(colWidth / linePitch) * linePitch;
                    var extra = (colWidth - snapped) / 2;
                    paddingH += extra;
                    gap = paddingH * 2;
                    colWidth = snapped;
                }
            }

            document.body.style.columnWidth = colWidth + 'px';
            document.body.style.columnGap = gap + 'px';
            document.body.style.height = vh + 'px';
            document.body.style.padding = paddingV + 'px ' + paddingH + 'px';
            document.body.style.columnFill = 'auto';

            document.body.offsetHeight;

            var scrollW = document.body.scrollWidth;
            return Math.max(1, Math.round(scrollW / vw));
        })();
        """

        return await withCheckedContinuation { cont in
            webView.evaluateJavaScript(measureJS) { result, _ in
                cont.resume(returning: (result as? Int) ?? 1)
            }
        }
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

// MARK: - Pagination Cache

/// Simple file-based cache for page counts. Keyed by a string that encodes
/// book identity + viewport + font size + theme.
final class PaginationCache: @unchecked Sendable {
    static let shared = PaginationCache()

    private let cacheDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalibreRead")
            .appendingPathComponent("PaginationCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Maximum age for cache entries (7 days).
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    func load(key: String, chapterCount: Int) -> [Int]? {
        let url = cacheDir.appendingPathComponent(safeFilename(key))
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }

        // Validate freshness and chapter count
        guard Date().timeIntervalSince(entry.date) < maxAge,
              entry.counts.count == chapterCount else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return entry.counts
    }

    func save(key: String, counts: [Int]) {
        let url = cacheDir.appendingPathComponent(safeFilename(key))
        let entry = CacheEntry(date: Date(), counts: counts)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func invalidate(key: String) {
        let url = cacheDir.appendingPathComponent(safeFilename(key))
        try? FileManager.default.removeItem(at: url)
    }

    private func safeFilename(_ key: String) -> String {
        let hash = key.utf8.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return "\(hash).json"
    }

    private struct CacheEntry: Codable {
        let date: Date
        let counts: [Int]
    }
}
