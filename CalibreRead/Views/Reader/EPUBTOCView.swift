import SwiftUI

struct EPUBTOCView: View {
    let toc: [FoliateTOCItem]
    let currentTocLabel: String?
    let pageController: FoliatePageController
    @Binding var isPresented: Bool

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
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let count = toc.count
                        if count > 0 {
                            ForEach(0..<count, id: \.self) { (index: Int) in
                                let item = toc[index]
                                let isCurrent = item.label == currentTocLabel
                                Button {
                                    pageController.goTo(item.href)
                                    isPresented = false
                                } label: {
                                    Text(item.label)
                                        .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .padding(.leading, CGFloat(item.depth) * 16)
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
                                .id(index)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if let currentIndex = toc.firstIndex(where: { $0.label == currentTocLabel }) {
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 340, height: 500)
    }
}
