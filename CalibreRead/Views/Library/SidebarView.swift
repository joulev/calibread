import SwiftUI

struct SidebarView: View {
    @Environment(LibraryManager.self) private var library

    var body: some View {
        @Bindable var library = library

        List {
            Section("Library") {
                Button {
                    library.clearFilters()
                } label: {
                    Label("All Books", systemImage: "books.vertical")
                }
                .buttonStyle(.plain)
                .fontWeight(library.selectedAuthor == nil && library.selectedTag == nil && library.selectedSeries == nil ? .semibold : .regular)
            }

            Section("Authors") {
                ForEach(library.authors) { author in
                    Button {
                        library.clearFilters()
                        library.selectedAuthor = author
                    } label: {
                        Label(author.name, systemImage: "person")
                    }
                    .buttonStyle(.plain)
                    .fontWeight(library.selectedAuthor == author ? .semibold : .regular)
                }
            }

            Section("Series") {
                ForEach(library.seriesList) { series in
                    Button {
                        library.clearFilters()
                        library.selectedSeries = series
                    } label: {
                        Label(series.name, systemImage: "text.book.closed")
                    }
                    .buttonStyle(.plain)
                    .fontWeight(library.selectedSeries == series ? .semibold : .regular)
                }
            }

            Section("Tags") {
                ForEach(library.tags) { tag in
                    Button {
                        library.clearFilters()
                        library.selectedTag = tag
                    } label: {
                        Label(tag.name, systemImage: "tag")
                    }
                    .buttonStyle(.plain)
                    .fontWeight(library.selectedTag == tag ? .semibold : .regular)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
    }
}
