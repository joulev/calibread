import WebKit

/// Serves app resources and EPUB files to WKWebView via the `calibre://` custom URL scheme.
///
/// Routes:
/// - `calibre://app/<path>` → serves files from the app bundle's Resources directory
/// - `calibre://book` → serves the EPUB file bytes as `application/epub+zip`
@MainActor
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    var bookURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "calibre" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let host = url.host() ?? ""

        if host == "book" {
            serveBook(urlSchemeTask)
        } else if host == "app" {
            serveAppResource(url.path(), urlSchemeTask)
        } else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op — responses are delivered synchronously
    }

    private func respond(_ task: any WKURLSchemeTask, data: Data, mimeType: String) {
        let url = task.request.url!
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ]
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func serveBook(_ task: any WKURLSchemeTask) {
        guard let bookURL, let data = try? Data(contentsOf: bookURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        respond(task, data: data, mimeType: "application/epub+zip")
    }

    private func serveAppResource(_ path: String, _ task: any WKURLSchemeTask) {
        // path is e.g. "/reader.html" or "/foliate/view.js"
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Map to bundle resource
        let resourceURL: URL?
        if cleanPath.hasPrefix("foliate/") {
            // Serve from Resources/foliate/ directory
            let subpath = String(cleanPath.dropFirst("foliate/".count))
            let components = subpath.split(separator: "/").map(String.init)
            if components.count == 1 {
                let name = (components[0] as NSString).deletingPathExtension
                let ext = (components[0] as NSString).pathExtension
                resourceURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "foliate")
            } else if components.count == 2 && components[0] == "vendor" {
                let name = (components[1] as NSString).deletingPathExtension
                let ext = (components[1] as NSString).pathExtension
                resourceURL = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "foliate/vendor")
            } else {
                resourceURL = nil
            }
        } else {
            let name = (cleanPath as NSString).deletingPathExtension
            let ext = (cleanPath as NSString).pathExtension
            resourceURL = Bundle.main.url(forResource: name, withExtension: ext)
        }

        guard let resourceURL, let data = try? Data(contentsOf: resourceURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mimeType = mimeTypeForExtension((cleanPath as NSString).pathExtension)
        respond(task, data: data, mimeType: mimeType)
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
