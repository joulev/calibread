import SwiftUI

struct EPUBBottomBar: View {
    let theme: ReaderTheme
    let currentFraction: Double
    let currentTocLabel: String?
    let groupCurrentPage: Int?
    let groupTotalPages: Int?
    let currentGlobalPage: Int?
    let totalBookPages: Int?
    let paginationProgress: (completed: Int, total: Int)?
    let namedGroupDividerFractions: [Double]
    let isRTLOrVertical: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                chapterInfo
                Spacer()
                overallProgress
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)

            progressBar
        }
    }

    private var chapterInfo: some View {
        HStack(spacing: 6) {
            Text(currentTocLabel?.isEmpty == false ? currentTocLabel! : "Unnamed Chapter")
                .lineLimit(1)
            if let page = groupCurrentPage, let total = groupTotalPages {
                Text("\u{00B7}")
                    .foregroundStyle(theme.swiftUISecondary.opacity(0.5))
                Text("\(page) / \(total)")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.swiftUISecondary)
    }

    @ViewBuilder
    private var overallProgress: some View {
        if let current = currentGlobalPage, let total = totalBookPages {
            Text("p. \(current) / \(total)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.swiftUISecondary)
        } else if let progress = paginationProgress, progress.total > 0 {
            Text("Calculating\u{2026} \(Int(round(Double(progress.completed) / Double(progress.total) * 100)))%")
                .font(.system(size: 11))
                .foregroundStyle(theme.swiftUISecondary.opacity(0.5))
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.swiftUISecondary.opacity(0.12))

                Rectangle()
                    .fill(theme.swiftUISecondary.opacity(0.35))
                    .frame(width: barWidth * currentFraction)

                let dividers = namedGroupDividerFractions
                ForEach(0..<dividers.count, id: \.self) { i in
                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.4))
                        .frame(width: 1.5)
                        .offset(x: barWidth * dividers[i])
                }
            }
            .scaleEffect(x: isRTLOrVertical ? -1 : 1)
        }
        .frame(height: ReaderConstants.progressBarHeight)
    }
}
