import SwiftUI
import WebKit

/// Relocate event data from foliate-js.
struct RelocateInfo {
    let fraction: Double
    let cfi: String?
    let tocLabel: String?
    let sectionPage: Int?
    let sectionPages: Int?
    let sectionIndex: Int?
    let totalSections: Int?
}

/// TOC entry received from foliate-js.
struct FoliateTOCItem: Identifiable {
    let id = UUID()
    let label: String
    let href: String
    let depth: Int
}

/// Controller providing direct JS access to foliate-js for snappy navigation.
@MainActor
@Observable
final class FoliatePageController {
    fileprivate weak var webView: WKWebView?

    func next() {
        webView?.evaluateJavaScript("CalibreBridge.next()", completionHandler: nil)
    }

    func prev() {
        webView?.evaluateJavaScript("CalibreBridge.prev()", completionHandler: nil)
    }

    func goLeft() {
        webView?.evaluateJavaScript("CalibreBridge.goLeft()", completionHandler: nil)
    }

    func goRight() {
        webView?.evaluateJavaScript("CalibreBridge.goRight()", completionHandler: nil)
    }

    func goTo(_ target: String) {
        let escaped = target.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("CalibreBridge.goTo('\(escaped)')", completionHandler: nil)
    }

    func goToFraction(_ fraction: Double) {
        webView?.evaluateJavaScript("CalibreBridge.goToFraction(\(fraction))", completionHandler: nil)
    }

    func setStyles(_ css: String) {
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        webView?.evaluateJavaScript("CalibreBridge.setStyles(`\(escaped)`)", completionHandler: nil)
    }

    func setLayout(gap: String? = nil, maxInlineSize: Int? = nil, maxColumnCount: Int? = nil) {
        let gapArg = gap.map { "'\($0)'" } ?? "null"
        let maxInlineArg = maxInlineSize.map { String($0) } ?? "null"
        let maxColArg = maxColumnCount.map { String($0) } ?? "null"
        webView?.evaluateJavaScript("CalibreBridge.setLayout(\(gapArg), \(maxInlineArg), \(maxColArg))", completionHandler: nil)
    }

    func initLocation(_ cfi: String) {
        let escaped = cfi.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("CalibreBridge.init('\(escaped)')", completionHandler: nil)
    }

    func initFraction(_ fraction: Double) {
        webView?.evaluateJavaScript("CalibreBridge.init({ fraction: \(fraction) })", completionHandler: nil)
    }
}

struct FoliateWebView: NSViewRepresentable {
    let bookURL: URL
    let theme: ReaderTheme
    let fontSize: Int
    let controller: FoliatePageController
    let lastCFI: String?
    let lastFraction: Double?

    let onRelocate: ((RelocateInfo) -> Void)?
    let onBookReady: (([FoliateTOCItem], [Double], [Int], String) -> Void)?
    let onWritingModeDetected: ((Bool) -> Void)?
    let onKeydown: ((String) -> Void)?
    let onPaginationComplete: (([Int]?) -> Void)?
    let onPaginationProgress: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onRelocate: onRelocate,
            onBookReady: onBookReady,
            onWritingModeDetected: onWritingModeDetected,
            onKeydown: onKeydown,
            onPaginationComplete: onPaginationComplete,
            onPaginationProgress: onPaginationProgress
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let schemeHandler = EPUBSchemeHandler()
        schemeHandler.bookURL = bookURL

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "calibre")

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "pageHandler")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.webView = webView
        context.coordinator.controller = controller
        context.coordinator.theme = theme
        context.coordinator.fontSize = fontSize
        context.coordinator.lastCFI = lastCFI
        context.coordinator.lastFraction = lastFraction

        controller.webView = webView

        // Load the reader shell
        webView.load(URLRequest(url: URL(string: "calibre://app/reader.html")!))

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRelocate = onRelocate
        context.coordinator.onBookReady = onBookReady
        context.coordinator.onWritingModeDetected = onWritingModeDetected
        context.coordinator.onKeydown = onKeydown
        context.coordinator.onPaginationComplete = onPaginationComplete
        context.coordinator.onPaginationProgress = onPaginationProgress

        controller.webView = webView

        if context.coordinator.theme != theme || context.coordinator.fontSize != fontSize {
            context.coordinator.theme = theme
            context.coordinator.fontSize = fontSize
            applyTheme(in: webView)
        }
    }

    private func applyTheme(in webView: WKWebView) {
        let css = theme.css(fontSize: fontSize)
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        webView.evaluateJavaScript("CalibreBridge.setStyles(`\(escaped)`)", completionHandler: nil)
    }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var controller: FoliatePageController?
        var theme: ReaderTheme = .light
        var fontSize: Int = 18
        var lastCFI: String?
        var lastFraction: Double?
        var bookOpened = false

        var onRelocate: ((RelocateInfo) -> Void)?
        var onBookReady: (([FoliateTOCItem], [Double], [Int], String) -> Void)?
        var onWritingModeDetected: ((Bool) -> Void)?
        var onKeydown: ((String) -> Void)?
        var onPaginationComplete: (([Int]?) -> Void)?
        var onPaginationProgress: ((Int, Int) -> Void)?

        private var didDisableScrollers = false

        init(
            onRelocate: ((RelocateInfo) -> Void)?,
            onBookReady: (([FoliateTOCItem], [Double], [Int], String) -> Void)?,
            onWritingModeDetected: ((Bool) -> Void)?,
            onKeydown: ((String) -> Void)?,
            onPaginationComplete: (([Int]?) -> Void)?,
            onPaginationProgress: ((Int, Int) -> Void)?
        ) {
            self.onRelocate = onRelocate
            self.onBookReady = onBookReady
            self.onWritingModeDetected = onWritingModeDetected
            self.onKeydown = onKeydown
            self.onPaginationComplete = onPaginationComplete
            self.onPaginationProgress = onPaginationProgress
        }

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

            guard !bookOpened else { return }
            bookOpened = true

            // Open the book — bridge.js will post "bookReady" when done,
            // at which point we apply theme and restore position.
            // Wait for modules to be ready (CalibreBridge defined on window)
            let openJS = """
            // Poll until CalibreBridge is available (modules load async)
            while (!window.CalibreBridge) await new Promise(r => setTimeout(r, 10));
            return await CalibreBridge.open()
            """
            webView.callAsyncJavaScript(openJS, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .failure(let error):
                    print("[CalibreBridge] open error: \(error)")
                case .success:
                    break
                }
            }
        }

        private func applyThemeAndRestore() {
            let css = theme.css(fontSize: fontSize)
            let escapedCSS = css.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            webView?.evaluateJavaScript("CalibreBridge.setStyles(`\(escapedCSS)`)", completionHandler: nil)
            webView?.evaluateJavaScript("CalibreBridge.setLayout('5%', 720, 1)", completionHandler: nil)

            // Restore reading position
            if let cfi = lastCFI, !cfi.isEmpty {
                let escaped = cfi.replacingOccurrences(of: "'", with: "\\'")
                webView?.evaluateJavaScript("CalibreBridge.init('\(escaped)')", completionHandler: nil)
            } else if let fraction = lastFraction, fraction > 0 {
                webView?.evaluateJavaScript("CalibreBridge.init({ fraction: \(fraction) })", completionHandler: nil)
            } else {
                webView?.evaluateJavaScript("CalibreBridge.init(null)", completionHandler: nil)
            }

            // Start background pagination measurement
            webView?.evaluateJavaScript("CalibreBridge.startPagination()", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "pageHandler",
                  let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }

            switch type {
            case "relocate":
                let info = RelocateInfo(
                    fraction: dict["fraction"] as? Double ?? 0,
                    cfi: dict["cfi"] as? String,
                    tocLabel: dict["tocLabel"] as? String,
                    sectionPage: dict["sectionPage"] as? Int,
                    sectionPages: dict["sectionPages"] as? Int,
                    sectionIndex: dict["sectionIndex"] as? Int,
                    totalSections: dict["totalSections"] as? Int
                )
                onRelocate?(info)

            case "bookReady":
                let tocDicts = dict["toc"] as? [[String: Any]] ?? []
                let toc = tocDicts.map { d in
                    FoliateTOCItem(
                        label: d["label"] as? String ?? "",
                        href: d["href"] as? String ?? "",
                        depth: d["depth"] as? Int ?? 0
                    )
                }
                let sectionFractions = dict["sectionFractions"] as? [Double] ?? []
                let sectionGroups = dict["sectionGroups"] as? [Int] ?? []
                let dir = dict["dir"] as? String ?? "ltr"
                onBookReady?(toc, sectionFractions, sectionGroups, dir)
                applyThemeAndRestore()

            case "load":
                let isVertical = dict["isVertical"] as? Bool ?? false
                onWritingModeDetected?(isVertical)

            case "keydown":
                let key = dict["key"] as? String ?? ""
                onKeydown?(key)

            case "paginationStarted":
                onPaginationComplete?(nil)

            case "paginationComplete":
                if let counts = dict["counts"] as? [Int] {
                    onPaginationComplete?(counts)
                }

            case "paginationProgress":
                let completed = dict["completed"] as? Int ?? 0
                let total = dict["total"] as? Int ?? 0
                onPaginationProgress?(completed, total)

            case "error":
                let message = dict["message"] as? String ?? "Unknown error"
                print("[CalibreBridge] JS error: \(message)")

            default:
                break
            }
        }
    }
}
