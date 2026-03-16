import SwiftUI

enum SidebarItem: Hashable {
    case allBooks
    case author(CalibreAuthor)
    case series(CalibreSeries)
    case tag(CalibreTag)
}

struct SidebarView: View {
    @Environment(LibraryManager.self) private var library

    var selection: SidebarItem? {
        if let author = library.selectedAuthor { return .author(author) }
        if let series = library.selectedSeries { return .series(series) }
        if let tag = library.selectedTag { return .tag(tag) }
        if library.selectedAuthor == nil && library.selectedSeries == nil && library.selectedTag == nil {
            return .allBooks
        }
        return nil
    }

    var body: some View {
        List(selection: Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                library.clearFilters()
                switch newValue {
                case .allBooks:
                    break
                case .author(let author):
                    library.selectedAuthor = author
                case .series(let series):
                    library.selectedSeries = series
                case .tag(let tag):
                    library.selectedTag = tag
                }
            }
        )) {
            Section("Library") {
                Label("All Books", systemImage: "books.vertical")
                    .tag(SidebarItem.allBooks)
            }

            Section("Authors") {
                ForEach(library.authors, id: \.id) { author in
                    Label(author.name, systemImage: "person")
                        .tag(SidebarItem.author(author))
                }
            }

            Section("Series") {
                ForEach(library.seriesList, id: \.id) { series in
                    Label(series.name, systemImage: "text.book.closed")
                        .tag(SidebarItem.series(series))
                }
            }

            Section("Tags") {
                ForEach(library.tags, id: \.id) { tag in
                    Label(tag.name, systemImage: "tag")
                        .tag(SidebarItem.tag(tag))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
    }
}
