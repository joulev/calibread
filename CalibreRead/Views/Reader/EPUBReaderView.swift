import SwiftUI
import SwiftData
import AppKit

struct EPUBReaderView: View {
    let bookURL: URL
    let libraryRoot: URL
    let bookTitle: String
    let bookId: String

    @State private var epubService: EPUBService?
    @State private var currentChapterIndex = 0
    @State private var showTOC = false
    @State private var theme: ReaderTheme = .light
    @State private var fontSize = 18
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var pageCommand: EPUBWebView.PageCommand = .none
    @State private var showControls = false
    @State private var showFontMenu = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background matching theme
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
        .onAppear(perform: loadEPUB)
        .onDisappear(perform: saveProgress)
        .onKeyPress(.leftArrow) {
            handlePrevPage()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            handleNextPage()
            return .handled
        }
        .onKeyPress(.space) {
            handleNextPage()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .sheet(isPresented: $showTOC) {
            if let service = epubService {
                TableOfContentsView(
                    chapters: service.tableOfContents,
                    currentIndex: currentChapterIndex
                ) { index in
                    navigateToChapter(index)
                    showTOC = false
                }
            }
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(service: EPUBService) -> some View {
        VStack(spacing: 0) {
            // Top toolbar
            topBar(service: service)

            // Main reading area
            EPUBWebView(
                fileURL: service.chapters[currentChapterIndex].fileURL,
                theme: theme,
                fontSize: fontSize,
                onPageInfo: { page, total in
                    handlePageInfo(page: page, total: total, service: service)
                },
                pageCommand: $pageCommand
            )

            // Bottom page indicator
            bottomBar(service: service)
        }
    }

    // MARK: - Top Bar

    private func topBar(service: EPUBService) -> some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.swiftUISecondary)

            Spacer()

            Text(bookTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.swiftUISecondary)
                .lineLimit(1)

            Spacer()

            // Font size controls
            HStack(spacing: 8) {
                Button {
                    fontSize = max(12, fontSize - 2)
                } label: {
                    Text("A")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.swiftUISecondary)

                Text("\(fontSize)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.swiftUISecondary)
                    .frame(width: 22)

                Button {
                    fontSize = min(32, fontSize + 2)
                } label: {
                    Text("A")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.swiftUISecondary)
            }

            // Theme picker
            Picker(selection: $theme) {
                ForEach(ReaderTheme.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // TOC button
            Button { showTOC = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.swiftUISecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.swiftUIBackground)
    }

    // MARK: - Bottom Bar

    private func bottomBar(service: EPUBService) -> some View {
        HStack {
            // Previous chapter
            Button {
                navigateToChapter(currentChapterIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.swiftUISecondary)
            .disabled(currentChapterIndex <= 0)
            .opacity(currentChapterIndex <= 0 ? 0.3 : 1)

            Spacer()

            // Chapter info
            if let tocEntry = currentTOCEntry(service: service) {
                Text(tocEntry.title)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.swiftUISecondary)
                    .lineLimit(1)

                Text("  ·  ")
                    .foregroundStyle(theme.swiftUISecondary.opacity(0.5))
            }

            Text("Page \(currentPage) of \(totalPages)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.swiftUISecondary)

            Spacer()

            // Next chapter
            Button {
                navigateToChapter(currentChapterIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.swiftUISecondary)
            .disabled(currentChapterIndex >= service.chapters.count - 1)
            .opacity(currentChapterIndex >= service.chapters.count - 1 ? 0.3 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(theme.swiftUIBackground)
    }

    // MARK: - Helpers

    private func currentTOCEntry(service: EPUBService) -> EPUBService.Chapter? {
        let currentFileURL = service.chapters[currentChapterIndex].fileURL
        // Find the matching TOC entry for this chapter's file
        return service.tableOfContents.last { tocChapter in
            let tocBase = tocChapter.href.components(separatedBy: "#").first ?? tocChapter.href
            let currentBase = currentFileURL.lastPathComponent
            return tocBase.hasSuffix(currentBase) || currentBase.hasSuffix(tocBase)
        }
    }

    // MARK: - Page Info Handler

    private func handlePageInfo(page: Int, total: Int, service: EPUBService) {
        if page == -1 {
            // Next chapter signal from JS
            handleNextChapter(service: service)
        } else if page == -2 {
            // Previous chapter signal from JS
            handlePrevChapter(service: service)
        } else {
            currentPage = page
            totalPages = total
        }
    }

    // MARK: - Navigation

    private func handleNextPage() {
        pageCommand = .next
    }

    private func handlePrevPage() {
        pageCommand = .previous
    }

    private func handleNextChapter(service: EPUBService) {
        if currentChapterIndex < service.chapters.count - 1 {
            currentChapterIndex += 1
            currentPage = 1
            saveProgress()
        }
    }

    private func handlePrevChapter(service: EPUBService) {
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            currentPage = 1
            // Go to last page of previous chapter
            pageCommand = .goTo(1.0)
            saveProgress()
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

    private func navigateToChapter(_ index: Int) {
        guard let service = epubService,
              index >= 0, index < service.chapters.count else { return }
        currentChapterIndex = index
        currentPage = 1
        saveProgress()
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
