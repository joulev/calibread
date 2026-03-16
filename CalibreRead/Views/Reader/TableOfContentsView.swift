import SwiftUI

struct TableOfContentsView: View {
    let chapters: [EPUBService.Chapter]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let count = chapters.count
                        if count > 0 {
                            ForEach(0..<count, id: \.self) { (index: Int) in
                                TocPopoverRow(
                                    chapter: chapters[index],
                                    isCurrent: chapters[index].id == currentIndex,
                                    onSelect: onSelect
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
        .frame(width: 340, height: 500)
    }
}

private struct TocPopoverRow: View {
    let chapter: EPUBService.Chapter
    let isCurrent: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        Button {
            onSelect(chapter.id)
        } label: {
            HStack {
                Text(chapter.title)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(chapter.id)
    }
}
