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

            List {
                ForEach(chapters, id: \.id) { chapter in
                    Button {
                        onSelect(chapter.id)
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .fontWeight(chapter.id == currentIndex ? .semibold : .regular)
                            Spacer()
                            if chapter.id == currentIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}
