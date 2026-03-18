import SwiftUI
import SwiftData
import AppKit

// MARK: - Constants

private enum ReaderConstants {
    static let minFontSize = 12
    static let maxFontSize = 32
    static let fontSizeStep = 2
    static let defaultFontSize = 18
    static let progressBarHeight: CGFloat = 3
}

struct EPUBReaderView: View {
    let bookURL: URL
    let libraryRoot: URL
    let bookTitle: String
    let bookId: String
    var onClose: (() -> Void)?

    @State private var showTOC = false
    @State private var showFontPanel = false
    @State private var theme: ReaderTheme = .sepia
    @State private var fontSize = ReaderConstants.defaultFontSize
    @State private var pageController = FoliatePageController()
    @State private var isHoveringLeft = false
    @State private var isHoveringRight = false
    @State private var isVerticalText = false

    // Progress state from foliate-js relocate events
    @State private var currentFraction: Double = 0
    @State private var currentCFI: String?
    @State private var currentTocLabel: String?
    @State private var sectionPage: Int?
    @State private var sectionTotalPages: Int?
    @State private var currentSectionIndex: Int?

    // Accurate page counts from background pagination measurement
    @State private var allSectionPageCounts: [Int]?
    @State private var paginationProgress: (completed: Int, total: Int)?

    // Book metadata from foliate-js
    @State private var toc: [FoliateTOCItem] = []
    @State private var sectionFractions: [Double] = []
    @State private var sectionGroups: [Int] = []  // maps section index → group start index
    @State private var bookDir: String = "ltr"
    @State private var bookReady = false

    // Saved position for restoration
    @State private var savedCFI: String?
    @State private var savedFraction: Double?

    @Environment(\.modelContext) private var modelContext

    /// Total pages in the book (nil while pagination is in progress).
    private var totalBookPages: Int? {
        allSectionPageCounts?.reduce(0, +)
    }

    /// Current global page number (nil while pagination is in progress).
    private var currentGlobalPage: Int? {
        guard let counts = allSectionPageCounts,
              let sectionIdx = currentSectionIndex,
              let page = sectionPage,
              sectionIdx < counts.count else { return nil }
        let pagesBefore = counts.prefix(sectionIdx).reduce(0, +)
        return pagesBefore + page
    }

    /// The range of section indices in the current named chapter group.
    private var currentGroupRange: Range<Int>? {
        guard let sectionIdx = currentSectionIndex,
              sectionIdx < sectionGroups.count else { return nil }
        let groupStart = sectionGroups[sectionIdx]
        // Find end: next section whose group start differs
        var groupEnd = sectionIdx + 1
        while groupEnd < sectionGroups.count && sectionGroups[groupEnd] == groupStart {
            groupEnd += 1
        }
        return groupStart..<groupEnd
    }

    /// Total pages across the current named chapter group.
    private var groupTotalPages: Int? {
        guard let range = currentGroupRange,
              let counts = allSectionPageCounts else { return nil }
        return counts[range].reduce(0, +)
    }

    /// Current page within the current named chapter group.
    private var groupCurrentPage: Int? {
        guard let range = currentGroupRange,
              let sectionIdx = currentSectionIndex,
              let page = sectionPage,
              let counts = allSectionPageCounts else { return nil }
        let pagesBefore = counts[range.lowerBound..<sectionIdx].reduce(0, +)
        return pagesBefore + page
    }

    /// Section fractions filtered to only show dividers at named chapter group boundaries.
    private var namedGroupDividerFractions: [Double] {
        guard !sectionGroups.isEmpty else { return sectionFractions }
        return sectionFractions.enumerated().compactMap { i, frac in
            // A divider appears at section i if it starts a new group
            // (i.e. sectionGroups[i] == i, meaning it's a named section)
            guard i < sectionGroups.count else { return nil as Double? }
            return sectionGroups[i] == i ? frac : nil
        }
    }

    var body: some View {
        ZStack {
            theme.swiftUIBackground
                .ignoresSafeArea()

            if bookReady || savedCFI != nil || savedFraction != nil || true {
                readerContent()
            }
        }
        .navigationTitle(bookTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar, .automatic)
        .preferredColorScheme(theme == .dark ? .dark : .light)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showTOC.toggle() } label: {
                    Label("Contents", systemImage: "list.bullet")
                }
                .popover(isPresented: $showTOC, arrowEdge: .bottom) {
                    tocView()
                }

                Button { showFontPanel.toggle() } label: {
                    Label("Appearance", systemImage: "textformat.size")
                }
                .popover(isPresented: $showFontPanel, arrowEdge: .bottom) {
                    fontControlsPanel()
                }
            }
        }
        .onAppear(perform: restoreProgress)
        .onDisappear(perform: saveProgress)
        .onKeyPress(.leftArrow) {
            pageController.goLeft()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            pageController.goRight()
            return .handled
        }
        .onKeyPress(.space) {
            pageController.next()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose?()
            return .handled
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                navigationArrow(isLeft: true)

                FoliateWebView(
                    bookURL: bookURL,
                    theme: theme,
                    fontSize: fontSize,
                    controller: pageController,
                    lastCFI: savedCFI,
                    lastFraction: savedFraction,
                    onRelocate: { info in
                        currentFraction = info.fraction
                        currentCFI = info.cfi
                        currentTocLabel = info.tocLabel
                        sectionPage = info.sectionPage
                        sectionTotalPages = info.sectionPages
                        currentSectionIndex = info.sectionIndex
                    },
                    onBookReady: { tocItems, fractions, groups, dir in
                        toc = tocItems
                        sectionFractions = fractions
                        sectionGroups = groups
                        bookDir = dir
                        bookReady = true
                    },
                    onWritingModeDetected: { vertical in
                        isVerticalText = vertical
                    },
                    onKeydown: { key in
                        if key == "ArrowLeft" { pageController.goLeft() }
                        else if key == "ArrowRight" { pageController.goRight() }
                        else if key == " " { pageController.next() }
                    },
                    onPaginationComplete: { counts in
                        allSectionPageCounts = counts
                        if counts != nil { paginationProgress = nil }
                    },
                    onPaginationProgress: { completed, total in
                        paginationProgress = (completed, total)
                    }
                )

                navigationArrow(isLeft: false)
            }

            bottomBar()
        }
    }

    // MARK: - Font Controls Panel

    private func fontControlsPanel() -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Button {
                    fontSize = max(ReaderConstants.minFontSize, fontSize - ReaderConstants.fontSizeStep)
                } label: {
                    Text("A")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                        )
                }
                .buttonStyle(.plain)

                Text("\(fontSize)px")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)

                Button {
                    fontSize = min(ReaderConstants.maxFontSize, fontSize + ReaderConstants.fontSizeStep)
                } label: {
                    Text("A")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                        )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Button {
                        theme = t
                    } label: {
                        Circle()
                            .fill(t.swiftUIBackground)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        theme == t ? Color.accentColor : Color.gray.opacity(0.3),
                                        lineWidth: theme == t ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Navigation Arrows

    private func navigationArrow(isLeft: Bool) -> some View {
        let isHovering = isLeft ? isHoveringLeft : isHoveringRight

        return Button {
            if isLeft { pageController.goLeft() }
            else { pageController.goRight() }
        } label: {
            Text(isLeft ? "\u{2039}" : "\u{203A}")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(theme.swiftUISecondary.opacity(isHovering ? 0.8 : 0.35))
                .frame(maxHeight: .infinity)
                .frame(width: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                if isLeft {
                    isHoveringLeft = hovering
                } else {
                    isHoveringRight = hovering
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar() -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                // Left: current TOC section + section page progress
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

                Spacer()

                // Right: overall book progress in pages
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
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Progress bar with section markers
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.12))

                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.35))
                        .frame(width: barWidth * currentFraction)

                    // Only show dividers at named chapter group boundaries
                    let dividers = namedGroupDividerFractions
                    ForEach(0..<dividers.count, id: \.self) { i in
                        Rectangle()
                            .fill(theme.swiftUISecondary.opacity(0.4))
                            .frame(width: 1.5)
                            .offset(x: barWidth * dividers[i])
                    }
                }
                .scaleEffect(x: (isVerticalText || bookDir == "rtl") ? -1 : 1)
            }
            .frame(height: ReaderConstants.progressBarHeight)
        }
    }

    // MARK: - TOC View

    private func tocView() -> some View {
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
                                    showTOC = false
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

    // MARK: - Persistence

    private func saveProgress() {
        let bookIdValue = bookId
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate<ReadingProgress> { $0.bookIdentifier == bookIdValue }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.scrollPosition = currentFraction
            existing.cfi = currentCFI
            existing.lastReadDate = Date()
        } else {
            let progress = ReadingProgress(
                bookIdentifier: bookId,
                format: "EPUB",
                scrollPosition: currentFraction,
                cfi: currentCFI
            )
            modelContext.insert(progress)
        }
        try? modelContext.save()
    }

    private func restoreProgress() {
        let bookIdValue = bookId
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate<ReadingProgress> { $0.bookIdentifier == bookIdValue }
        )
        if let progress = try? modelContext.fetch(descriptor).first {
            savedCFI = progress.cfi
            if progress.scrollPosition > 0 {
                savedFraction = progress.scrollPosition
            }
        }
    }
}
