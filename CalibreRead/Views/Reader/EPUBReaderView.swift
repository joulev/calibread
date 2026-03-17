import SwiftUI
import SwiftData
import AppKit

struct EPUBReaderView: View {
    let bookURL: URL
    let libraryRoot: URL
    let bookTitle: String
    let bookId: String
    var onClose: (() -> Void)?

    @State private var epubService: EPUBService?
    @State private var currentChapterIndex = 0
    @State private var showTOC = false
    @State private var showFontPanel = false
    @State private var theme: ReaderTheme = .sepia
    @State private var fontSize = 18
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var pageController = EPUBPageController()
    @State private var isHoveringLeft = false
    @State private var isHoveringRight = false
    @State private var isContentReady = false
    @State private var isVerticalText = false

    // Pagination state
    @State private var sectionPageCounts: [Int]? = nil
    @State private var paginationProgress = 0
    @State private var paginationTask: Task<Void, Never>?
    @State private var contentSize: CGSize = .zero

    @Environment(\.modelContext) private var modelContext

    // MARK: - Computed Progress

    /// Total pages in the entire book (nil if pagination hasn't completed).
    private var totalBookPages: Int? {
        sectionPageCounts?.reduce(0, +)
    }

    /// Current global page number (nil if pagination hasn't completed).
    private var currentGlobalPage: Int? {
        guard let counts = sectionPageCounts else { return nil }
        let previousPages = counts.prefix(currentChapterIndex).reduce(0, +)
        return previousPages + currentPage
    }

    /// Overall reading progress as a fraction 0...1.
    /// Uses actual page counts when available, falls back to chapter-weighted estimate.
    private var overallProgress: Double {
        if let global = currentGlobalPage, let total = totalBookPages, total > 0 {
            return Double(global) / Double(total)
        }
        // Fallback: equal-weight chapters
        guard let service = epubService, !service.chapters.isEmpty else { return 0 }
        let chapterFraction = totalPages > 1 ? Double(currentPage - 1) / Double(totalPages - 1) : 0
        return (Double(currentChapterIndex) + chapterFraction) / Double(service.chapters.count)
    }

    /// Title of the current section. If the current spine chapter has a direct
    /// TOC match, use that. Otherwise walk backward through spine chapters to
    /// find the most recent one with a TOC entry. Falls back to "Unnamed Chapter".
    private var currentChapterTitle: String {
        guard let service = epubService else { return "Unnamed Chapter" }
        for i in stride(from: currentChapterIndex, through: 0, by: -1) {
            let href = service.chapters[i].href
            let base = href.components(separatedBy: "#").first ?? href
            if let tocEntry = service.tableOfContents.first(where: { toc in
                let tocBase = toc.href.components(separatedBy: "#").first ?? toc.href
                return tocBase == base
                    || tocBase.hasSuffix("/\(base)")
                    || base.hasSuffix("/\(tocBase)")
            }) {
                return tocEntry.title
            }
        }
        return "Unnamed Chapter"
    }

    var body: some View {
        ZStack {
            theme.swiftUIBackground
                .ignoresSafeArea()

            if let service = epubService, !service.chapters.isEmpty {
                readerContent(service: service)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if let service = epubService {
                        TableOfContentsView(
                            chapters: service.tableOfContents,
                            currentChapterHref: service.chapters[currentChapterIndex].href
                        ) { tocChapter in
                            navigateToTOCEntry(tocChapter)
                            showTOC = false
                        }
                    }
                }

                Button { showFontPanel.toggle() } label: {
                    Label("Appearance", systemImage: "textformat.size")
                }
                .popover(isPresented: $showFontPanel, arrowEdge: .bottom) {
                    fontControlsPanel()
                }
            }
        }
        .onAppear(perform: loadEPUB)
        .onDisappear {
            saveProgress()
            paginationTask?.cancel()
        }
        .onKeyPress(.leftArrow) {
            guard isContentReady else { return .handled }
            // In vertical text, left arrow = forward (next page)
            if isVerticalText {
                pageController.nextPage()
            } else {
                pageController.previousPage()
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isContentReady else { return .handled }
            // In vertical text, right arrow = backward (previous page)
            if isVerticalText {
                pageController.previousPage()
            } else {
                pageController.nextPage()
            }
            return .handled
        }
        .onKeyPress(.space) {
            guard isContentReady else { return .handled }
            pageController.nextPage()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose?()
            return .handled
        }
        .onChange(of: fontSize) { _, _ in
            startPagination()
        }
        .onChange(of: theme) { _, _ in
            startPagination()
        }
        .onChange(of: contentSize) { _, _ in
            startPagination()
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(service: EPUBService) -> some View {
        VStack(spacing: 0) {
            // Main content area with side navigation arrows
            HStack(spacing: 0) {
                navigationArrow(isLeft: true)

                GeometryReader { geo in
                    EPUBWebView(
                        fileURL: service.chapters[currentChapterIndex].fileURL,
                        contentBaseURL: service.contentRootURL,
                        theme: theme,
                        fontSize: fontSize,
                        controller: pageController,
                        onPageInfo: { page, total in
                            currentPage = page
                            totalPages = total
                            // Keep paginated counts in sync with the live WKWebView
                            if var counts = sectionPageCounts, currentChapterIndex < counts.count {
                                counts[currentChapterIndex] = total
                                sectionPageCounts = counts
                            }
                        },
                        onChapterEnd: { edge in
                            isContentReady = false
                            switch edge {
                            case .next:
                                if currentChapterIndex < service.chapters.count - 1 {
                                    currentChapterIndex += 1
                                    currentPage = 1
                                    saveProgress()
                                }
                            case .previous:
                                if currentChapterIndex > 0 {
                                    currentChapterIndex -= 1
                                    currentPage = 1
                                    pageController.pendingFraction = 1.0
                                    saveProgress()
                                }
                            }
                        },
                        onContentReadyChanged: { ready in
                            isContentReady = ready
                        },
                        onWritingModeDetected: { vertical in
                            isVerticalText = vertical
                        }
                    )
                    .onAppear {
                        if geo.size.width > 0, geo.size.height > 0 {
                            contentSize = geo.size
                        }
                    }
                    .onChange(of: geo.size) { _, newSize in
                        if newSize.width > 0, newSize.height > 0 {
                            contentSize = newSize
                        }
                    }
                }

                navigationArrow(isLeft: false)
            }

            bottomBar(service: service)
        }
    }

    // MARK: - Font Controls Panel

    private func fontControlsPanel() -> some View {
        VStack(spacing: 16) {
            // Font size controls
            HStack(spacing: 16) {
                Button {
                    fontSize = max(12, fontSize - 2)
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
                    fontSize = min(32, fontSize + 2)
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

            // Theme picker
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

        // In vertical text (tategaki), reading goes right-to-left,
        // so the left button = forward (next) and right button = backward (prev)
        let goForward = isVerticalText ? isLeft : !isLeft

        return Button {
            guard isContentReady else { return }
            if goForward {
                pageController.nextPage()
            } else {
                pageController.previousPage()
            }
        } label: {
            Text(isLeft ? "\u{2039}" : "\u{203A}")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(theme.swiftUISecondary.opacity(isContentReady ? (isHovering ? 0.8 : 0.35) : 0.1))
                .frame(maxHeight: .infinity)
                .frame(width: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isContentReady)
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

    private func bottomBar(service: EPUBService) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                // Left: section info (hidden during content transitions)
                HStack(spacing: 6) {
                    Text(currentChapterTitle)
                        .lineLimit(1)

                    Text("\u{00B7}")
                        .foregroundStyle(theme.swiftUISecondary.opacity(0.5))

                    Text("\(currentPage) / \(totalPages)")
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.swiftUISecondary)
                .opacity(isContentReady ? 1 : 0)

                Spacer()

                // Right: global page position (hidden during content transitions)
                if let globalPage = currentGlobalPage, let totalBook = totalBookPages {
                    Text("p. \(globalPage) / \(totalBook)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.swiftUISecondary)
                        .opacity(isContentReady ? 1 : 0)
                } else {
                    Text("Paginating\u{2026} \(paginationProgress)/\(service.chapters.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.swiftUISecondary.opacity(0.5))
                        .opacity(isContentReady ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // Progress bar with section markers
            // For vertical (RTL) text, the bar fills from right to left
            GeometryReader { geometry in
                let barWidth = geometry.size.width
                ZStack(alignment: isVerticalText ? .trailing : .leading) {
                    // Track
                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.12))

                    // Fill
                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.35))
                        .frame(width: barWidth * overallProgress)
                        .animation(.easeInOut(duration: 0.25), value: overallProgress)

                    // Section dividers (only when pagination is complete)
                    if let counts = sectionPageCounts, let total = totalBookPages, total > 0 {
                        let dividers = sectionDividerOffsets(counts: counts, total: total)
                        ForEach(0..<dividers.count, id: \.self) { i in
                            // In trailing-aligned ZStack, offset is relative to the right edge
                            let offset = isVerticalText
                                ? -(barWidth * dividers[i])
                                : barWidth * dividers[i]
                            Rectangle()
                                .fill(theme.swiftUISecondary.opacity(0.2))
                                .frame(width: 1)
                                .offset(x: offset)
                        }
                    }
                }
            }
            .frame(height: 3)
        }
    }

    /// Compute the fractional x-offsets for section dividers on the progress bar.
    private func sectionDividerOffsets(counts: [Int], total: Int) -> [Double] {
        guard total > 0, counts.count > 1 else { return [] }
        var offsets: [Double] = []
        var cumulative = 0
        // Skip the last section — we don't need a divider at the very end
        for i in 0..<(counts.count - 1) {
            cumulative += counts[i]
            offsets.append(Double(cumulative) / Double(total))
        }
        return offsets
    }

    // MARK: - Pagination

    private func startPagination() {
        guard let service = epubService,
              contentSize.width > 0, contentSize.height > 0 else { return }

        paginationTask?.cancel()
        sectionPageCounts = nil
        paginationProgress = 0

        paginationTask = Task {
            // Small debounce for rapid changes (font size adjustment, window resize)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let paginator = EPUBPaginator(
                chapters: service.chapters,
                contentBaseURL: service.contentRootURL,
                theme: theme,
                fontSize: fontSize,
                viewportSize: contentSize,
                bookIdentifier: bookId
            )

            let counts = await paginator.measureAll { progress in
                paginationProgress = progress
            }

            guard !Task.isCancelled, let counts else { return }
            sectionPageCounts = counts
        }
    }

    // MARK: - Actions

    private func loadEPUB() {
        do {
            let service = try EPUBService(bookURL: bookURL, libraryRoot: libraryRoot)
            self.epubService = service
            restoreProgress()
            // Pagination starts once contentSize is reported via onChange
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// Navigate to a TOC entry by matching its href against the spine chapters.
    private func navigateToTOCEntry(_ tocChapter: EPUBService.Chapter) {
        guard let service = epubService else { return }
        let tocBase = tocChapter.href.components(separatedBy: "#").first ?? tocChapter.href
        if let spineIndex = service.chapters.firstIndex(where: { spine in
            let spineBase = spine.href.components(separatedBy: "#").first ?? spine.href
            return spineBase == tocBase
                || spineBase.hasSuffix("/\(tocBase)")
                || tocBase.hasSuffix("/\(spineBase)")
        }) {
            currentChapterIndex = spineIndex
            currentPage = 1
            saveProgress()
        }
    }

    private func saveProgress() {
        let bookIdValue = bookId
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate<ReadingProgress> { $0.bookIdentifier == bookIdValue }
        )
        let position = totalPages > 1 ? Double(currentPage - 1) / Double(totalPages - 1) : 0
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.chapterIndex = currentChapterIndex
            existing.scrollPosition = position
            existing.lastReadDate = Date()
        } else {
            let progress = ReadingProgress(
                bookIdentifier: bookId,
                format: "EPUB",
                chapterIndex: currentChapterIndex,
                scrollPosition: position
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
            currentChapterIndex = progress.chapterIndex
            if progress.scrollPosition > 0 {
                pageController.pendingFraction = progress.scrollPosition
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Spacer()
                }

                Text("Failed to parse EPUB file")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                Divider()

                Text("Diagnostic Details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
