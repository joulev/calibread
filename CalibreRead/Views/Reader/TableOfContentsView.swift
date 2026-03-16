import SwiftUI

struct TableOfContentsView: View {
    let chapters: [EPUBService.Chapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Table of Contents")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    tocRows
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    @ViewBuilder
    private var tocRows: some View {
        let count = chapters.count
        if count > 0 {
            ForEach(0..<count, id: \.self) { (index: Int) -> TocRow in
                TocRow(
                    chapter: chapters[index],
                    isCurrent: chapters[index].id == currentIndex,
                    onSelect: onSelect
                )
            }
        }
    }
}

private struct TocRow: View {
    let chapter: EPUBService.Chapter
    let isCurrent: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        Button {
            onSelect(chapter.id)
        } label: {
            HStack {
                Text(chapter.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
