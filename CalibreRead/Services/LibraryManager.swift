import Foundation
import SwiftUI

/// Manages the state of the currently opened Calibre library.
@MainActor
@Observable
final class LibraryManager {
    private(set) var books: [CalibreBook] = []
    private(set) var authors: [CalibreAuthor] = []
    private(set) var tags: [CalibreTag] = []
    private(set) var seriesList: [CalibreSeries] = []
    private(set) var isLoaded = false
    private(set) var errorMessage: String?

    var libraryURL: URL? {
        didSet {
            if let url = libraryURL {
                persistLibraryPath(url)
                loadLibrary(from: url)
            }
        }
    }

    // MARK: - Filtering and sorting

    var searchText = ""
    var selectedAuthor: CalibreAuthor?
    var selectedTag: CalibreTag?
    var selectedSeries: CalibreSeries?
    var sortOrder: SortOrder = .recent
    var lastOpenedDates: [String: Date] = [:]

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case series = "Series"

        var id: String { rawValue }
    }

    var filteredBooks: [CalibreBook] {
        var result = books

        if let author = selectedAuthor {
            result = result.filter { $0.authors.contains(author) }
        }
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        if let series = selectedSeries {
            result = result.filter { $0.series == series }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { book in
                book.title.lowercased().contains(query)
                    || book.authorNames.lowercased().contains(query)
                    || (book.series?.name.lowercased().contains(query) ?? false)
                    || book.tags.contains(where: { $0.name.lowercased().contains(query) })
            }
        }

        switch sortOrder {
        case .recent:
            result.sort { a, b in
                let dateA = lastOpenedDates[a.uuid]
                let dateB = lastOpenedDates[b.uuid]
                switch (dateA, dateB) {
                case let (da?, db?):
                    return da > db
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.sortTitle.localizedCaseInsensitiveCompare(b.sortTitle) == .orderedAscending
                }
            }
        case .series:
            result.sort { a, b in
                switch (a.series, b.series) {
                case let (sa?, sb?):
                    let cmp = sa.sort.localizedCaseInsensitiveCompare(sb.sort)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return a.seriesIndex < b.seriesIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.sortTitle.localizedCaseInsensitiveCompare(b.sortTitle) == .orderedAscending
                }
            }
        }

        return result
    }

    // MARK: - Library loading

    func loadLibrary(from url: URL) {
        do {
            let database = try CalibreDatabase(libraryURL: url)
            self.books = try database.fetchAllBooks()
            self.authors = try database.fetchAllAuthors().sorted { $0.sort < $1.sort }
            self.tags = try database.fetchAllTags().sorted { $0.name < $1.name }
            self.seriesList = try database.fetchAllSeries().sorted { $0.sort < $1.sort }
            self.isLoaded = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Failed to load library: \(error.localizedDescription)"
            self.isLoaded = false
        }
    }

    func clearFilters() {
        selectedAuthor = nil
        selectedTag = nil
        selectedSeries = nil
        searchText = ""
    }

    // MARK: - Library path persistence

    private static let libraryPathKey = "calibreLibraryPath"

    func restoreSavedLibrary() {
        guard let path = UserDefaults.standard.string(forKey: Self.libraryPathKey) else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("metadata.db").path) else { return }
        self.libraryURL = url
    }

    private func persistLibraryPath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.libraryPathKey)
    }
}
