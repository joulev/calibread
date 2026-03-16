import Foundation
import SQLite

/// Read-only interface to a Calibre library's metadata.db
final class CalibreDatabase {
    private let db: Connection

    // MARK: - Table definitions

    private let books = Table("books")
    private let authors = Table("authors")
    private let tags = Table("tags")
    private let series = Table("series")
    private let publishers = Table("publishers")
    private let ratings = Table("ratings")
    private let languages = Table("languages")
    private let comments = Table("comments")
    private let data = Table("data")
    private let booksAuthorsLink = Table("books_authors_link")
    private let booksTagsLink = Table("books_tags_link")
    private let booksSeriesLink = Table("books_series_link")
    private let booksPublishersLink = Table("books_publishers_link")
    private let booksRatingsLink = Table("books_ratings_link")
    private let booksLanguagesLink = Table("books_languages_link")

    // MARK: - Column definitions

    private let colId = SQLite.Expression<Int64>("id")
    private let colTitle = SQLite.Expression<String>("title")
    private let colSort = SQLite.Expression<String?>("sort")
    private let colAuthorSort = SQLite.Expression<String?>("author_sort")
    private let colTimestamp = SQLite.Expression<String?>("timestamp")
    private let colPubdate = SQLite.Expression<String?>("pubdate")
    private let colSeriesIndex = SQLite.Expression<Double>("series_index")
    private let colPath = SQLite.Expression<String>("path")
    private let colUuid = SQLite.Expression<String?>("uuid")
    private let colHasCover = SQLite.Expression<Bool>("has_cover")
    private let colLastModified = SQLite.Expression<String?>("last_modified")

    private let colName = SQLite.Expression<String>("name")
    private let colLink = SQLite.Expression<String?>("link")

    private let colBook = SQLite.Expression<Int64>("book")
    private let colAuthor = SQLite.Expression<Int64>("author")
    private let colTag = SQLite.Expression<Int64>("tag")
    private let colSeriesFK = SQLite.Expression<Int64>("series")
    private let colPublisher = SQLite.Expression<Int64>("publisher")
    private let colRating = SQLite.Expression<Int64>("rating")
    private let colLangCode = SQLite.Expression<Int64>("lang_code")

    private let colFormat = SQLite.Expression<String>("format")
    private let colDataName = SQLite.Expression<String>("name")
    private let colUncompressedSize = SQLite.Expression<Int64>("uncompressed_size")

    private let colText = SQLite.Expression<String?>("text")
    private let colRatingValue = SQLite.Expression<Int64>("rating")

    private let colLangCodeValue = SQLite.Expression<String>("lang_code")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Initialization

    init(libraryURL: URL) throws {
        let dbPath = libraryURL.appendingPathComponent("metadata.db").path
        db = try Connection(dbPath, readonly: true)
    }

    // MARK: - Fetching all books

    func fetchAllBooks() throws -> [CalibreBook] {
        let allAuthors = try fetchAllAuthors()
        let allTags = try fetchAllTags()
        let allSeries = try fetchAllSeries()
        let authorLinks = try fetchAuthorLinks()
        let tagLinks = try fetchTagLinks()
        let seriesLinks = try fetchSeriesLinks()
        let allFormats = try fetchAllFormats()
        let allComments = try fetchComments()
        let allRatings = try fetchRatings()
        let publisherLinks = try fetchPublisherLinks()
        let allPublishers = try fetchAllPublishers()

        let authorsById = Dictionary(uniqueKeysWithValues: allAuthors.map { ($0.id, $0) })
        let tagsById = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        let seriesById = Dictionary(uniqueKeysWithValues: allSeries.map { ($0.id, $0) })
        let publishersById = Dictionary(uniqueKeysWithValues: allPublishers.map { ($0.id, $0) })

        var booksList: [CalibreBook] = []

        for row in try db.prepare(books) {
            let bookId = row[colId]

            var book = CalibreBook(
                id: bookId,
                title: row[colTitle],
                sortTitle: row[colSort] ?? row[colTitle],
                authorSort: row[colAuthorSort] ?? "",
                timestamp: row[colTimestamp].flatMap(Self.parseDate),
                pubdate: row[colPubdate].flatMap(Self.parseDate),
                seriesIndex: row[colSeriesIndex],
                path: row[colPath],
                uuid: row[colUuid] ?? "",
                hasCover: row[colHasCover],
                lastModified: row[colLastModified].flatMap(Self.parseDate)
            )

            book.authors = (authorLinks[bookId] ?? []).compactMap { authorsById[$0] }
            book.tags = (tagLinks[bookId] ?? []).compactMap { tagsById[$0] }
            book.formats = allFormats[bookId] ?? []
            book.comment = allComments[bookId]
            book.rating = allRatings[bookId]

            if let seriesId = seriesLinks[bookId] {
                book.series = seriesById[seriesId]
            }

            if let publisherId = publisherLinks[bookId] {
                book.publisher = publishersById[publisherId]?.name
            }

            booksList.append(book)
        }

        return booksList
    }

    // MARK: - Entity fetchers

    func fetchAllAuthors() throws -> [CalibreAuthor] {
        try db.prepare(authors).map { row in
            CalibreAuthor(
                id: row[colId],
                name: row[colName],
                sort: row[colSort] ?? row[colName],
                link: row[colLink] ?? ""
            )
        }
    }

    func fetchAllTags() throws -> [CalibreTag] {
        try db.prepare(tags).map { row in
            CalibreTag(id: row[colId], name: row[colName])
        }
    }

    func fetchAllSeries() throws -> [CalibreSeries] {
        try db.prepare(series).map { row in
            CalibreSeries(id: row[colId], name: row[colName], sort: row[colSort] ?? row[colName])
        }
    }

    // MARK: - Private helpers

    private func fetchAllPublishers() throws -> [(id: Int64, name: String)] {
        try db.prepare(publishers).map { row in
            (id: row[colId], name: row[colName])
        }
    }

    private func fetchAuthorLinks() throws -> [Int64: [Int64]] {
        var map: [Int64: [Int64]] = [:]
        for row in try db.prepare(booksAuthorsLink) {
            map[row[colBook], default: []].append(row[colAuthor])
        }
        return map
    }

    private func fetchTagLinks() throws -> [Int64: [Int64]] {
        var map: [Int64: [Int64]] = [:]
        for row in try db.prepare(booksTagsLink) {
            map[row[colBook], default: []].append(row[colTag])
        }
        return map
    }

    private func fetchSeriesLinks() throws -> [Int64: Int64] {
        var map: [Int64: Int64] = [:]
        for row in try db.prepare(booksSeriesLink) {
            map[row[colBook]] = row[colSeriesFK]
        }
        return map
    }

    private func fetchPublisherLinks() throws -> [Int64: Int64] {
        var map: [Int64: Int64] = [:]
        for row in try db.prepare(booksPublishersLink) {
            map[row[colBook]] = row[colPublisher]
        }
        return map
    }

    private func fetchAllFormats() throws -> [Int64: [BookFormat]] {
        var map: [Int64: [BookFormat]] = [:]
        for row in try db.prepare(data) {
            let format = BookFormat(
                id: row[colId],
                bookId: row[colBook],
                format: row[colFormat],
                name: row[colDataName],
                uncompressedSize: row[colUncompressedSize]
            )
            map[row[colBook], default: []].append(format)
        }
        return map
    }

    private func fetchComments() throws -> [Int64: String] {
        var map: [Int64: String] = [:]
        for row in try db.prepare(comments) {
            if let text = row[colText] {
                map[row[colBook]] = text
            }
        }
        return map
    }

    private func fetchRatings() throws -> [Int64: Int] {
        let ratingValues: [Int64: Int] = try {
            var map: [Int64: Int] = [:]
            for row in try db.prepare(ratings) {
                map[row[colId]] = Int(row[colRatingValue])
            }
            return map
        }()

        var map: [Int64: Int] = [:]
        for row in try db.prepare(booksRatingsLink) {
            if let value = ratingValues[row[colRating]] {
                map[row[colBook]] = value
            }
        }
        return map
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }
}
