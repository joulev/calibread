import Foundation
import SQLite

/// Read-only interface to a Calibre library's metadata.db
final class CalibreDatabase {
    private let db: Connection

    // MARK: - Table definitions

    private let booksTable = Table("books")
    private let authorsTable = Table("authors")
    private let tagsTable = Table("tags")
    private let seriesTable = Table("series")
    private let publishersTable = Table("publishers")
    private let ratingsTable = Table("ratings")
    private let languagesTable = Table("languages")
    private let commentsTable = Table("comments")
    private let dataTable = Table("data")
    private let booksAuthorsLink = Table("books_authors_link")
    private let booksTagsLink = Table("books_tags_link")
    private let booksSeriesLink = Table("books_series_link")
    private let booksPublishersLink = Table("books_publishers_link")
    private let booksRatingsLink = Table("books_ratings_link")
    private let booksLanguagesLink = Table("books_languages_link")

    // MARK: - Shared column definitions

    private let idColumn = SQLite.Expression<Int64>("id")
    private let nameColumn = SQLite.Expression<String>("name")
    private let sortColumn = SQLite.Expression<String?>("sort")
    private let linkColumn = SQLite.Expression<String?>("link")
    private let bookFKColumn = SQLite.Expression<Int64>("book")

    // MARK: - Books table columns

    private let titleColumn = SQLite.Expression<String>("title")
    private let authorSortColumn = SQLite.Expression<String?>("author_sort")
    private let timestampColumn = SQLite.Expression<String?>("timestamp")
    private let pubdateColumn = SQLite.Expression<String?>("pubdate")
    private let seriesIndexColumn = SQLite.Expression<Double>("series_index")
    private let pathColumn = SQLite.Expression<String>("path")
    private let uuidColumn = SQLite.Expression<String?>("uuid")
    private let hasCoverColumn = SQLite.Expression<Bool>("has_cover")
    private let lastModifiedColumn = SQLite.Expression<String?>("last_modified")

    // MARK: - Junction table FK columns

    private let authorFKColumn = SQLite.Expression<Int64>("author")
    private let tagFKColumn = SQLite.Expression<Int64>("tag")
    private let seriesFKColumn = SQLite.Expression<Int64>("series")
    private let publisherFKColumn = SQLite.Expression<Int64>("publisher")
    private let ratingFKColumn = SQLite.Expression<Int64>("rating")
    private let langCodeFKColumn = SQLite.Expression<Int64>("lang_code")

    // MARK: - Data table columns

    private let formatColumn = SQLite.Expression<String>("format")
    private let dataNameColumn = SQLite.Expression<String>("name")
    private let uncompressedSizeColumn = SQLite.Expression<Int64>("uncompressed_size")

    // MARK: - Other table columns

    private let commentTextColumn = SQLite.Expression<String?>("text")
    private let ratingValueColumn = SQLite.Expression<Int64>("rating")
    private let langCodeValueColumn = SQLite.Expression<String>("lang_code")

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

        for row in try db.prepare(booksTable) {
            let bookId = row[idColumn]

            var book = CalibreBook(
                id: bookId,
                title: row[titleColumn],
                sortTitle: row[sortColumn] ?? row[titleColumn],
                authorSort: row[authorSortColumn] ?? "",
                timestamp: row[timestampColumn].flatMap(Self.parseDate),
                pubdate: row[pubdateColumn].flatMap(Self.parseDate),
                seriesIndex: row[seriesIndexColumn],
                path: row[pathColumn],
                uuid: row[uuidColumn] ?? "",
                hasCover: row[hasCoverColumn],
                lastModified: row[lastModifiedColumn].flatMap(Self.parseDate)
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
        try db.prepare(authorsTable).map { row in
            CalibreAuthor(
                id: row[idColumn],
                name: row[nameColumn],
                sort: row[sortColumn] ?? row[nameColumn],
                link: row[linkColumn] ?? ""
            )
        }
    }

    func fetchAllTags() throws -> [CalibreTag] {
        try db.prepare(tagsTable).map { row in
            CalibreTag(id: row[idColumn], name: row[nameColumn])
        }
    }

    func fetchAllSeries() throws -> [CalibreSeries] {
        try db.prepare(seriesTable).map { row in
            CalibreSeries(id: row[idColumn], name: row[nameColumn], sort: row[sortColumn] ?? row[nameColumn])
        }
    }

    // MARK: - Private helpers

    private func fetchAllPublishers() throws -> [(id: Int64, name: String)] {
        try db.prepare(publishersTable).map { row in
            (id: row[idColumn], name: row[nameColumn])
        }
    }

    private func fetchAuthorLinks() throws -> [Int64: [Int64]] {
        var map: [Int64: [Int64]] = [:]
        for row in try db.prepare(booksAuthorsLink) {
            map[row[bookFKColumn], default: []].append(row[authorFKColumn])
        }
        return map
    }

    private func fetchTagLinks() throws -> [Int64: [Int64]] {
        var map: [Int64: [Int64]] = [:]
        for row in try db.prepare(booksTagsLink) {
            map[row[bookFKColumn], default: []].append(row[tagFKColumn])
        }
        return map
    }

    private func fetchSeriesLinks() throws -> [Int64: Int64] {
        var map: [Int64: Int64] = [:]
        for row in try db.prepare(booksSeriesLink) {
            map[row[bookFKColumn]] = row[seriesFKColumn]
        }
        return map
    }

    private func fetchPublisherLinks() throws -> [Int64: Int64] {
        var map: [Int64: Int64] = [:]
        for row in try db.prepare(booksPublishersLink) {
            map[row[bookFKColumn]] = row[publisherFKColumn]
        }
        return map
    }

    private func fetchAllFormats() throws -> [Int64: [BookFormat]] {
        var map: [Int64: [BookFormat]] = [:]
        for row in try db.prepare(dataTable) {
            let format = BookFormat(
                id: row[idColumn],
                bookId: row[bookFKColumn],
                format: row[formatColumn],
                name: row[dataNameColumn],
                uncompressedSize: row[uncompressedSizeColumn]
            )
            map[row[bookFKColumn], default: []].append(format)
        }
        return map
    }

    private func fetchComments() throws -> [Int64: String] {
        var map: [Int64: String] = [:]
        for row in try db.prepare(commentsTable) {
            if let text = row[commentTextColumn] {
                map[row[bookFKColumn]] = text
            }
        }
        return map
    }

    private func fetchRatings() throws -> [Int64: Int] {
        let ratingValues: [Int64: Int] = try {
            var map: [Int64: Int] = [:]
            for row in try db.prepare(ratingsTable) {
                map[row[idColumn]] = Int(row[ratingValueColumn])
            }
            return map
        }()

        var map: [Int64: Int] = [:]
        for row in try db.prepare(booksRatingsLink) {
            if let value = ratingValues[row[ratingFKColumn]] {
                map[row[bookFKColumn]] = value
            }
        }
        return map
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }
}
