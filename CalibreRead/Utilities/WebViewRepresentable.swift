import SwiftUI
import WebKit

struct EPUBWebView: NSViewRepresentable {
    let fileURL: URL
    let cssURL: URL?
    let theme: ReaderTheme
    let fontSize: Int
    var onScrollPositionChanged: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollPositionChanged: onScrollPositionChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "scrollHandler")
        config.userContentController = userController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        loadContent(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollPositionChanged = onScrollPositionChanged

        // Check if we need to reload (different URL)
        if context.coordinator.currentURL != fileURL {
            loadContent(in: webView)
        } else {
            // Just update theme/font
            injectStyles(in: webView)
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
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var currentURL: URL?
        var onScrollPositionChanged: ((Double) -> Void)?

        init(onScrollPositionChanged: ((Double) -> Void)?) {
            self.onScrollPositionChanged = onScrollPositionChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL = webView.url

            // Inject scroll tracking
            let scrollJS = """
            window.addEventListener('scroll', function() {
                var scrollTop = document.documentElement.scrollTop || document.body.scrollTop;
                var scrollHeight = document.documentElement.scrollHeight || document.body.scrollHeight;
                var clientHeight = document.documentElement.clientHeight;
                var position = scrollTop / Math.max(1, scrollHeight - clientHeight);
                window.webkit.messageHandlers.scrollHandler.postMessage(position);
            });
            """
            webView.evaluateJavaScript(scrollJS, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "scrollHandler", let position = message.body as? Double {
                onScrollPositionChanged?(position)
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
        let (bg, fg) = colors
        return """
        body {
            font-family: 'Georgia', 'Times New Roman', serif !important;
            font-size: \(fontSize)px !important;
            line-height: 1.6 !important;
            max-width: 42em !important;
            margin: 2em auto !important;
            padding: 0 2em !important;
            background-color: \(bg) !important;
            color: \(fg) !important;
        }
        img {
            max-width: 100% !important;
            height: auto !important;
        }
        a {
            color: inherit !important;
        }
        """
    }

    private var colors: (bg: String, fg: String) {
        switch self {
        case .light: return ("#ffffff", "#1a1a1a")
        case .sepia: return ("#f4ecd8", "#5b4636")
        case .dark: return ("#1e1e1e", "#d4d4d4")
        }
    }
}
