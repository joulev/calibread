import SwiftUI

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
    @State private var scrollPosition: Double = 0

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Reader toolbar
            readerToolbar

            Divider()

            // Content
            if let service = epubService, !service.chapters.isEmpty {
                EPUBWebView(
                    fileURL: service.chapters[currentChapterIndex].fileURL,
                    cssURL: nil,
                    theme: theme,
                    fontSize: fontSize,
                    onScrollPositionChanged: { position in
                        scrollPosition = position
                    }
                )
            } else if let error = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(error)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Bottom bar with chapter navigation
            bottomBar
        }
        .onAppear(perform: loadEPUB)
        .onDisappear(perform: saveProgress)
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

    // MARK: - Toolbar

    private var readerToolbar: some View {
        HStack {
            Text(bookTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Font size controls
            Button { fontSize = max(12, fontSize - 2) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.borderless)

            Text("\(fontSize)px")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 40)

            Button { fontSize = min(32, fontSize + 2) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 20)

            // Theme picker
            Picker("Theme", selection: $theme) {
                ForEach(ReaderTheme.allCases) { t in
                    Label(t.rawValue, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Divider().frame(height: 20)

            // TOC button
            Button { showTOC = true } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                navigateToChapter(currentChapterIndex - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentChapterIndex <= 0)
            .buttonStyle(.borderless)

            Spacer()

            if let service = epubService {
                Text("Chapter \(currentChapterIndex + 1) of \(service.chapters.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                navigateToChapter(currentChapterIndex + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(epubService.map { currentChapterIndex >= $0.chapters.count - 1 } ?? true)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
        saveProgress()
    }

    private func saveProgress() {
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.bookIdentifier == bookId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.chapterIndex = currentChapterIndex
            existing.scrollPosition = scrollPosition
            existing.lastReadDate = Date()
        } else {
            let progress = ReadingProgress(
                bookIdentifier: bookId,
                format: "EPUB",
                chapterIndex: currentChapterIndex,
                scrollPosition: scrollPosition
            )
            modelContext.insert(progress)
        }
        try? modelContext.save()
    }

    private func restoreProgress() {
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.bookIdentifier == bookId }
        )
        if let progress = try? modelContext.fetch(descriptor).first {
            currentChapterIndex = progress.chapterIndex
        }
    }
}
