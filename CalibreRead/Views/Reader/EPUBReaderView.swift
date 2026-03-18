import SwiftUI
import SwiftData
import AppKit

// MARK: - Constants

enum ReaderConstants {
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
    @AppStorage("readerTheme") private var theme: ReaderTheme = .sepia
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
    @State private var sectionGroups: [Int] = []  // maps section index -> group start index
    @State private var bookDir: String = "ltr"
    @State private var bookReady = false

    // Saved position for restoration
    @State private var savedCFI: String?
    @State private var savedFraction: Double?

    @Environment(\.modelContext) private var modelContext

    // MARK: - Pagination computed properties

    private var totalBookPages: Int? {
        allSectionPageCounts?.reduce(0, +)
    }

    private var currentGlobalPage: Int? {
        guard let counts = allSectionPageCounts,
              let sectionIdx = currentSectionIndex,
              let page = sectionPage,
              sectionIdx < counts.count else { return nil }
        let pagesBefore = counts.prefix(sectionIdx).reduce(0, +)
        return pagesBefore + page
    }

    private var currentGroupRange: Range<Int>? {
        guard let sectionIdx = currentSectionIndex,
              sectionIdx < sectionGroups.count else { return nil }
        let groupStart = sectionGroups[sectionIdx]
        var groupEnd = sectionIdx + 1
        while groupEnd < sectionGroups.count && sectionGroups[groupEnd] == groupStart {
            groupEnd += 1
        }
        return groupStart..<groupEnd
    }

    private var groupTotalPages: Int? {
        guard let range = currentGroupRange,
              let counts = allSectionPageCounts else { return nil }
        return counts[range].reduce(0, +)
    }

    private var groupCurrentPage: Int? {
        guard let range = currentGroupRange,
              let sectionIdx = currentSectionIndex,
              let page = sectionPage,
              let counts = allSectionPageCounts else { return nil }
        let pagesBefore = counts[range.lowerBound..<sectionIdx].reduce(0, +)
        return pagesBefore + page
    }

    private var namedGroupDividerFractions: [Double] {
        guard !sectionGroups.isEmpty else { return sectionFractions }
        return sectionFractions.enumerated().compactMap { i, frac in
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
                    EPUBTOCView(
                        toc: toc,
                        currentTocLabel: currentTocLabel,
                        pageController: pageController,
                        isPresented: $showTOC
                    )
                }

                Button { showFontPanel.toggle() } label: {
                    Label("Appearance", systemImage: "textformat.size")
                }
                .popover(isPresented: $showFontPanel, arrowEdge: .bottom) {
                    EPUBFontControlsPanel(fontSize: $fontSize, theme: $theme)
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

            EPUBBottomBar(
                theme: theme,
                currentFraction: currentFraction,
                currentTocLabel: currentTocLabel,
                groupCurrentPage: groupCurrentPage,
                groupTotalPages: groupTotalPages,
                currentGlobalPage: currentGlobalPage,
                totalBookPages: totalBookPages,
                paginationProgress: paginationProgress,
                namedGroupDividerFractions: namedGroupDividerFractions,
                isRTLOrVertical: isVerticalText || bookDir == "rtl"
            )
        }
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
