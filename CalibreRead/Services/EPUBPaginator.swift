import WebKit

/// Measures page counts for all chapters in an EPUB using a pool of concurrent
/// WKWebViews. This is significantly faster than the sequential approach since
/// multiple chapters are measured in parallel.
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
            // Report instant completion
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
        var nextIndex = 0
        var completedCount = 0

        // Use a continuation-based approach to dispatch work across workers
        await withTaskGroup(of: (Int, Int)?.self) { group in
            // Seed each worker with initial work
            for worker in workers {
                guard nextIndex < chapters.count else { break }
                let index = nextIndex
                nextIndex += 1
                group.addTask { @MainActor in
                    let count = await worker.measure(chapter: self.chapters[index])
                    return (index, count)
                }
            }

            // As each completes, feed it the next chapter
            for await result in group {
                guard !Task.isCancelled else { break }
                guard let (index, count) = result else { continue }

                results[index] = count
                completedCount += 1
                onProgress(completedCount)

                // Assign next chapter to a worker
                if nextIndex < chapters.count {
                    let nextIdx = nextIndex
                    nextIndex += 1
                    // Find a free worker — we reuse them round-robin
                    let workerIdx = completedCount % workerCount
                    let worker = workers[workerIdx]
                    group.addTask { @MainActor in
                        let cnt = await worker.measure(chapter: self.chapters[nextIdx])
                        return (nextIdx, cnt)
                    }
                }
            }
        }

        guard !Task.isCancelled else {
            for worker in workers { worker.teardown() }
            return nil
        }

        // Tear down workers
        for worker in workers { worker.teardown() }

        // Cache results
        PaginationCache.shared.save(key: cacheKey, counts: results)

        return results
    }
}

// MARK: - Pagination Worker

/// A single WKWebView-based worker that can measure one chapter at a time.
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

    /// Measure page count for a single chapter.
    func measure(chapter: EPUBService.Chapter) async -> Int {
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

        return await measurePages()
    }

    /// Measure pages after waiting for all images and fonts to load.
    /// Combines asset waiting + measurement in a single JS evaluation to
    /// avoid extra round-trips.
    private func measurePages() async -> Int {
        let css = theme.css(fontSize: fontSize)
        let vw = Int(webView.frame.width)
        let vh = Int(webView.frame.height)

        // Step 1: Wait for all images and fonts via callAsyncJavaScript,
        // which natively awaits JS Promises.
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

        // callAsyncJavaScript handles `await` in the body natively
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            webView.callAsyncJavaScript(waitJS, arguments: [:], in: nil, in: .page) { _ in
                cont.resume()
            }
        }

        // Step 2: Now measure with all assets loaded
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
        // Simple hash to avoid filesystem issues with long/special character keys
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
