import SwiftUI
import PDFKit

struct PDFReaderKitView: NSViewRepresentable {
    let url: URL
    var onPageChanged: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true

        context.coordinator.pdfView = pdfView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
    }

    @MainActor
    class Coordinator: NSObject {
        var pdfView: PDFView?
        var onPageChanged: ((Int, Int) -> Void)?

        init(onPageChanged: ((Int, Int) -> Void)?) {
            self.onPageChanged = onPageChanged
        }

        @objc func pageChanged() {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let pageIndex = document.index(for: currentPage)
            let pageCount = document.pageCount
            onPageChanged?(pageIndex, pageCount)
        }
    }
}
