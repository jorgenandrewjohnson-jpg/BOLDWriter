import AppKit
import PDFKit
import SwiftUI

struct ProofPageNavigationState {
    var requestedPage: Int?

    mutating func shouldPublishVisiblePage(_ page: Int) -> Bool {
        guard let requestedPage else { return true }
        guard page == requestedPage else { return false }
        self.requestedPage = nil
        return true
    }
}

struct BookProofPreviewView: View {
    let data: Data
    let pageCount: Int
    let pageSettings: [PageSettings]
    @Environment(\.dismiss) private var dismiss
    @State private var page = 1
    @State private var pageEntry = "1"
    @State private var facingPages = false
    @State private var showMargins = true
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Print Proof").font(.headline)
                Divider().frame(height: 20)
                Button { navigate(to: 1) } label: { Image(systemName: "backward.end.fill") }
                    .help("First page")
                Button { navigate(to: max(1, page - 1)) } label: { Image(systemName: "chevron.left") }
                    .help("Previous page")
                TextField("Page", text: $pageEntry)
                    .frame(width: 60)
                    .accessibilityLabel("Go to proof page")
                    .onSubmit { navigateToEntry() }
                Button("Go", action: navigateToEntry)
                Text("of \(pageCount)").foregroundStyle(.secondary)
                Button { navigate(to: min(pageCount, page + 1)) } label: { Image(systemName: "chevron.right") }
                    .help("Next page")
                Button { navigate(to: pageCount) } label: { Image(systemName: "forward.end.fill") }
                    .help("Last page")
                Divider().frame(height: 20)
                Toggle("Facing pages", isOn: $facingPages)
                    .toggleStyle(.checkbox)
                Toggle("Safe margins", isOn: $showMargins)
                    .toggleStyle(.checkbox)
                Spacer()
                Button { zoom = max(0.5, zoom / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out")
                Button("Fit") { zoom = 1 }
                    .help("Fit page to window")
                Button { zoom = min(3, zoom * 1.2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
            Divider()
            PDFProofRepresentable(
                data: data,
                pageSettings: pageSettings,
                currentPage: $page,
                facingPages: $facingPages,
                showMargins: $showMargins,
                zoom: $zoom
            )
        }
        .frame(minWidth: 800, minHeight: 620)
        .onChange(of: page) { _, value in pageEntry = String(value) }
    }

    private func navigate(to requested: Int) {
        guard pageCount > 0 else { return }
        page = min(max(1, requested), pageCount)
        pageEntry = String(page)
    }

    private func navigateToEntry() {
        guard let value = Int(pageEntry) else { pageEntry = String(page); return }
        navigate(to: value)
    }
}

private struct PDFProofRepresentable: NSViewRepresentable {
    let data: Data
    let pageSettings: [PageSettings]
    @Binding var currentPage: Int
    @Binding var facingPages: Bool
    @Binding var showMargins: Bool
    @Binding var zoom: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        view.displayDirection = .horizontal
        view.document = PDFDocument(data: data)
        context.coordinator.view = view
        context.coordinator.installPageObserver()
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChanged = { currentPage = $0 }
        let wantedMode: PDFDisplayMode = facingPages ? .twoUpContinuous : .singlePageContinuous
        if view.displayMode != wantedMode { view.displayMode = wantedMode }
        view.autoScales = zoom == 1
        if zoom != 1 { view.scaleFactor = zoom }
        if let target = view.document?.page(at: max(0, currentPage - 1)), view.currentPage !== target {
            context.coordinator.navigate(view, to: target, pageNumber: currentPage)
        }
        if context.coordinator.lastMarginsEnabled != showMargins {
            applyMarginAnnotations(to: view.document)
            context.coordinator.lastMarginsEnabled = showMargins
        }
    }

    private func applyMarginAnnotations(to document: PDFDocument?) {
        guard let document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.userName == "BOLDWriterSafeMarginGuide" {
                page.removeAnnotation(annotation)
            }
            guard showMargins, pageSettings.indices.contains(index) else { continue }
            let settings = pageSettings[index]
            let media = page.bounds(for: .mediaBox)
            let rect = CGRect(
                x: media.minX + settings.leftMargin,
                y: media.minY + settings.bottomMargin,
                width: media.width - settings.leftMargin - settings.rightMargin,
                height: media.height - settings.topMargin - settings.bottomMargin
            )
            guard rect.width > 0, rect.height > 0 else { continue }
            let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            annotation.userName = "BOLDWriterSafeMarginGuide"
            annotation.color = .systemOrange
            annotation.border = PDFBorder()
            annotation.border?.lineWidth = 0.8
            annotation.border?.style = .dashed
            page.addAnnotation(annotation)
        }
    }

    final class Coordinator: NSObject {
        weak var view: PDFView?
        var onPageChanged: ((Int) -> Void)?
        var lastMarginsEnabled: Bool?
        var navigationState = ProofPageNavigationState()
        private var observer: NSObjectProtocol?

        func navigate(_ view: PDFView, to page: PDFPage, pageNumber: Int) {
            navigationState.requestedPage = pageNumber
            // PDFView may receive a binding update before its continuous-page
            // layout is ready. Schedule the jump after SwiftUI completes the
            // representable update, then retry once after PDFKit lays out the
            // destination page. Keep stale page notifications from changing
            // the requested page until the target becomes visible.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.navigationState.requestedPage == pageNumber else { return }
                view.layoutSubtreeIfNeeded()
                view.go(to: page)
                view.go(to: page.bounds(for: .cropBox), on: page)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak view] in
                    guard let self, let view, self.navigationState.requestedPage == pageNumber else { return }
                    view.go(to: page)
                    view.go(to: page.bounds(for: .cropBox), on: page)
                }
            }
        }

        func installPageObserver() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self, let index = self.view?.currentPage?.pageRef?.pageNumber else { return }
                // PDFKit can emit a notification for the previously visible page while
                // a programmatic jump is still being applied. Do not let that stale
                // notification undo the requested destination in SwiftUI state.
                guard self.navigationState.shouldPublishVisiblePage(index) else { return }
                self.onPageChanged?(index)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
