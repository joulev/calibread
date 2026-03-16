import SwiftUI
import WebKit

struct BookDetailView: View {
    let book: CalibreBook
    let libraryRoot: URL
    let onRead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover
                HStack {
                    Spacer()
                    coverImage
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    Spacer()
                }

                // Title and Author
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.title2.bold())

                    Text(book.authorNames)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Read button
                if book.preferredFormat != nil {
                    Button(action: onRead) {
                        Label("Read", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    if let series = book.seriesDescription {
                        metadataRow("Series", value: series)
                    }

                    if let publisher = book.publisher {
                        metadataRow("Publisher", value: publisher)
                    }

                    if let pubdate = book.pubdate {
                        metadataRow("Published", value: pubdate.formatted(date: .abbreviated, time: .omitted))
                    }

                    if let rating = book.rating, rating > 0 {
                        HStack {
                            Text("Rating")
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { star in
                                    Image(systemName: star < rating / 2 ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    if !book.formats.isEmpty {
                        metadataRow("Formats", value: book.formats.map(\.format).joined(separator: ", "))
                    }
                }

                // Tags
                if !book.tags.isEmpty {
                    Divider()
                    FlowLayout(spacing: 6) {
                        ForEach(book.tags) { tag in
                            Text(tag.name)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Description
                if let comment = book.comment, !comment.isEmpty {
                    Divider()
                    Text("Description")
                        .font(.headline)
                    HTMLTextView(html: comment)
                        .frame(minHeight: 100)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let url = book.coverURL(libraryRoot: libraryRoot),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 180, height: 280)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
        }
        .font(.subheadline)
    }
}

/// Simple flow layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

/// Renders HTML content (book descriptions from Calibre) using a lightweight web view.
struct HTMLTextView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        loadHTML(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadHTML(in: webView)
    }

    private func loadHTML(in webView: WKWebView) {
        let styledHTML = """
        <html>
        <head>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                color: -apple-system-label;
                margin: 0;
                padding: 0;
                -webkit-text-size-adjust: none;
            }
            @media (prefers-color-scheme: dark) {
                body { color: #e0e0e0; }
            }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }
}
