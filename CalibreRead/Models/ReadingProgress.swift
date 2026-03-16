import Foundation
import SwiftData

@Model
final class ReadingProgress {
    @Attribute(.unique) var bookIdentifier: String
    var format: String
    var chapterIndex: Int
    var scrollPosition: Double
    var lastReadDate: Date
    var isFinished: Bool

    init(bookIdentifier: String, format: String, chapterIndex: Int = 0, scrollPosition: Double = 0) {
        self.bookIdentifier = bookIdentifier
        self.format = format
        self.chapterIndex = chapterIndex
        self.scrollPosition = scrollPosition
        self.lastReadDate = Date()
        self.isFinished = false
    }
}

@Model
final class BookmarkEntry {
    var bookIdentifier: String
    var title: String
    var chapterIndex: Int
    var scrollPosition: Double
    var createdDate: Date

    init(bookIdentifier: String, title: String, chapterIndex: Int, scrollPosition: Double) {
        self.bookIdentifier = bookIdentifier
        self.title = title
        self.chapterIndex = chapterIndex
        self.scrollPosition = scrollPosition
        self.createdDate = Date()
    }
}
