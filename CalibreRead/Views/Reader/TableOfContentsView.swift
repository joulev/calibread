import SwiftUI

struct TableOfContentsView: View {
    let chapters: [EPUBService.Chapter]
    let currentChapterHref: String
    let onSelect: (EPUBService.Chapter) -> Void

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
                                let chapter = chapters[index]
                                TocPopoverRow(
                                    chapter: chapter,
                                    isCurrent: isCurrentChapter(chapter),
                                    onSelect: onSelect
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    // Scroll to the current chapter
                    if let current = chapters.first(where: { isCurrentChapter($0) }) {
                        proxy.scrollTo(current.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 340, height: 500)
    }

    private func isCurrentChapter(_ chapter: EPUBService.Chapter) -> Bool {
        HrefMatcher.matches(chapter.href, currentChapterHref)
    }
}

private struct TocPopoverRow: View {
    let chapter: EPUBService.Chapter
    let isCurrent: Bool
    let onSelect: (EPUBService.Chapter) -> Void

    var body: some View {
        Button {
            onSelect(chapter)
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
