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
    @State private var pageCommand: EPUBWebView.PageCommand = .none
    @State private var isHoveringLeft = false
    @State private var isHoveringRight = false

    @Environment(\.modelContext) private var modelContext

    private var readingProgress: Double {
        guard let service = epubService, !service.chapters.isEmpty else { return 0 }
        let chapterFraction = totalPages > 1 ? Double(currentPage - 1) / Double(totalPages - 1) : 0
        return (Double(currentChapterIndex) + chapterFraction) / Double(service.chapters.count)
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
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ControlGroup {
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
        }
        .onAppear(perform: loadEPUB)
        .onDisappear(perform: saveProgress)
        .onKeyPress(.leftArrow) {
            pageCommand = .previous
            return .handled
        }
        .onKeyPress(.rightArrow) {
            pageCommand = .next
            return .handled
        }
        .onKeyPress(.space) {
            pageCommand = .next
            return .handled
        }
        .onKeyPress(.escape) {
            onClose?()
            return .handled
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(service: EPUBService) -> some View {
        VStack(spacing: 0) {
            // Main content area with side navigation arrows
            ZStack {
                EPUBWebView(
                    fileURL: service.chapters[currentChapterIndex].fileURL,
                    contentBaseURL: service.contentRootURL,
                    theme: theme,
                    fontSize: fontSize,
                    onPageInfo: { page, total in
                        currentPage = page
                        totalPages = total
                    },
                    onChapterEnd: { edge in
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
                                pageCommand = .goTo(1.0)
                                saveProgress()
                            }
                        }
                    },
                    pageCommand: $pageCommand
                )

                // Side navigation arrows
                HStack(spacing: 0) {
                    navigationArrow(isLeft: true)
                    Spacer()
                    navigationArrow(isLeft: false)
                }
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

        return Button {
            pageCommand = isLeft ? .previous : .next
        } label: {
            Text(isLeft ? "\u{2039}" : "\u{203A}")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(theme.swiftUISecondary.opacity(isHovering ? 0.8 : 0.35))
                .frame(maxHeight: .infinity)
                .frame(width: 56)
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

    private func bottomBar(service: EPUBService) -> some View {
        VStack(spacing: 0) {
            Text("\(currentPage) of \(totalPages)")
                .font(.system(size: 12))
                .foregroundStyle(theme.swiftUISecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            // Reading progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.12))

                    Rectangle()
                        .fill(theme.swiftUISecondary.opacity(0.35))
                        .frame(width: geometry.size.width * readingProgress)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Actions

    private func loadEPUB() {
        do {
            let service = try EPUBService(bookURL: bookURL, libraryRoot: libraryRoot)
            self.epubService = service
            restoreProgress()
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
                pageCommand = .goTo(progress.scrollPosition)
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
