import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(LibraryManager.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @State private var selectedBook: CalibreBook?
    @State private var viewMode: ViewMode = .grid

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
    ]

    var body: some View {
        @Bindable var library = library

        VStack(spacing: 0) {
            switch viewMode {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(library.filteredBooks, id: \.id) { book in
                            BookGridItem(book: book, libraryRoot: library.libraryURL!)
                                .onTapGesture {
                                    selectedBook = book
                                }
                                .onTapGesture(count: 2) {
                                    openBook(book)
                                }
                        }
                    }
                    .padding()
                }
            case .list:
                List(selection: $selectedBook) {
                    ForEach(library.filteredBooks, id: \.id) { book in
                        BookListRow(book: book, libraryRoot: library.libraryURL!)
                            .tag(book)
                            .onTapGesture(count: 2) {
                                openBook(book)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle("\(library.filteredBooks.count) books")
        .searchable(text: Bindable(library).searchText, prompt: "Search books...")
        .toolbar {
            ToolbarItemGroup {
                Picker("Sort", selection: Bindable(library).sortOrder) {
                    ForEach(LibraryManager.SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }

                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear { loadLastOpenedDates() }
        .inspector(isPresented: .init(
            get: { selectedBook != nil },
            set: { if !$0 { selectedBook = nil } }
        )) {
            if let book = selectedBook {
                BookDetailView(book: book, libraryRoot: library.libraryURL!) {
                    openBook(book)
                }
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
            }
        }
    }

    private func openBook(_ book: CalibreBook) {
        guard let libraryRoot = library.libraryURL,
              let data = BookWindowData(book: book, libraryRoot: libraryRoot) else { return }
        recordBookOpened(book)
        openWindow(value: data)
    }

    private func loadLastOpenedDates() {
        let descriptor = FetchDescriptor<ReadingProgress>()
        guard let entries = try? modelContext.fetch(descriptor) else { return }
        var dates: [String: Date] = [:]
        for entry in entries {
            dates[entry.bookIdentifier] = entry.lastReadDate
        }
        library.lastOpenedDates = dates
    }

    private func recordBookOpened(_ book: CalibreBook) {
        let bookIdValue = book.uuid
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate<ReadingProgress> { $0.bookIdentifier == bookIdValue }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastReadDate = Date()
        } else {
            let progress = ReadingProgress(
                bookIdentifier: book.uuid,
                format: book.preferredFormat?.format ?? "UNKNOWN"
            )
            modelContext.insert(progress)
        }
        try? modelContext.save()
        library.lastOpenedDates[book.uuid] = Date()
    }

    private var navigationTitle: String {
        if let author = library.selectedAuthor { return author.name }
        if let tag = library.selectedTag { return tag.name }
        if let series = library.selectedSeries { return series.name }
        return "All Books"
    }
}
