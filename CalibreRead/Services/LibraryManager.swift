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
                persistLibraryBookmark(url)
                loadLibrary(from: url)
            }
        }
    }

    // MARK: - Filtering and sorting

    var searchText = ""
    var selectedAuthor: CalibreAuthor?
    var selectedTag: CalibreTag?
    var selectedSeries: CalibreSeries?
    var sortOrder: SortOrder = .title

    enum SortOrder: String, CaseIterable, Identifiable {
        case title = "Title"
        case author = "Author"
        case dateAdded = "Date Added"
        case datePublished = "Date Published"

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
        case .title:
            result.sort { $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending }
        case .author:
            result.sort { $0.authorSort.localizedCaseInsensitiveCompare($1.authorSort) == .orderedAscending }
        case .dateAdded:
            result.sort { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
        case .datePublished:
            result.sort { ($0.pubdate ?? .distantPast) > ($1.pubdate ?? .distantPast) }
        }

        return result
    }

    // MARK: - Library loading

    func loadLibrary(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

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

    // MARK: - Security-scoped bookmark persistence

    private static let bookmarkKey = "calibreLibraryBookmark"

    func restoreSavedLibrary() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            persistLibraryBookmark(url)
        }

        self.libraryURL = url
    }

    private func persistLibraryBookmark(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }
}
