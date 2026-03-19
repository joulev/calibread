import AppKit

extension String {
    func truncated(toWidth maxWidth: CGFloat, font: NSFont = .menuFont(ofSize: 0)) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (self as NSString).size(withAttributes: attributes).width <= maxWidth {
            return self
        }
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            let candidate = String(prefix(mid)) + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= maxWidth {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low > 0 ? String(prefix(low - 1)) + "…" : "…"
    }
}

@MainActor
@Observable
final class RecentBooksManager {
    static let shared = RecentBooksManager()

    private(set) var recentBooks: [BookWindowData] = []

    private let key = "recentBooks"
    private let maxCount = 5

    private init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let books = try? JSONDecoder().decode([BookWindowData].self, from: data)
        else { return }
        recentBooks = books
    }

    func addRecentBook(_ book: BookWindowData) {
        recentBooks.removeAll { $0.uuid == book.uuid }
        recentBooks.insert(book, at: 0)
        if recentBooks.count > maxCount { recentBooks = Array(recentBooks.prefix(maxCount)) }
        if let data = try? JSONEncoder().encode(recentBooks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
