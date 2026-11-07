import AppKit
import SwiftUI

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var controller: EditorController
    var printLayout: Bool
    var editingEnabled: Bool = true
    var showNonPrintingCharacters: Bool = false
    var showLineNumbers: Bool = false
    var showRuler: Bool = true
    var onContextLink: (() -> Void)? = nil
    var onContextComment: (() -> Void)? = nil
    var onContextSuggest: (() -> Void)? = nil
    var onContextSpelling: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(document: document, controller: controller) }

    var onImportManuscript: ((URL) -> Void)? = nil

    var onPaginationFailure: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = EditorScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.hasHorizontalRuler = showRuler
        scroll.rulersVisible = showRuler
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let canvas = PaginatedEditor(text: document.text)
        context.coordinator.canvas = canvas
        context.coordinator.lastAppliedRevisionID =
            document.revisionID

        canvas.onLayoutFailure = { message in
            DispatchQueue.main.async {
                if let onPaginationFailure { onPaginationFailure(message) }
                else { document.lastErrorMessage = message }
            }
        }
        canvas.onActiveViewRehomed = { [weak controller] view, selection in
            controller?.attach(view)
            controller?.updateSelection(selection)
        }

        canvas.configureTextView = { [weak coordinator = context.coordinator, weak controller, weak canvas] textView in
            textView.importManuscript = onImportManuscript
            textView.isRichText = true
            textView.isEditable = canvas?.editingEnabled ?? true
            textView.isSelectable = true
            textView.importsGraphics = true
            textView.allowsUndo = true
            let liveProofing =
                LargeDocumentPolicy
                    .allowsLiveProofing(
                        textLength:
                            document.text.length
                    )

            textView.isAutomaticSpellingCorrectionEnabled =
                false

            textView.isContinuousSpellCheckingEnabled =
                liveProofing

            textView.isGrammarCheckingEnabled =
                liveProofing

            textView.isAutomaticLinkDetectionEnabled =
                liveProofing
            textView.usesFindBar = true
            textView.usesRuler = true
            textView.isRulerVisible = showRuler
            textView.minSize = .zero
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.delegate = coordinator
            textView.setAccessibilityLabel("Document editor")
            textView.editFootnote = { [weak controller] in controller?.editSelectedFootnote() }
            textView.editEndnote = { [weak controller] in controller?.editSelectedEndnote() }
            textView.tableController = controller
            textView.contextInsertLink = onContextLink
            textView.contextAddComment = onContextComment
            textView.contextSuggestEdits = onContextSuggest
            textView.contextShowSpelling = onContextSpelling
            textView.floatingImageCanvas = canvas
        }
        canvas.configureTextView?(canvas.firstView)
        if document.text.length == 0 { canvas.firstView.typingAttributes = [.font: WriterStyle.defaultFont, .foregroundColor: NSColor.textColor] }
        scroll.documentView = canvas
        canvas.setEditingEnabled(
            editingEnabled
        )
        canvas.setShowsInvisibleCharacters(
            showNonPrintingCharacters
        )
        canvas.setShowsLineNumbers(
            showLineNumbers
        )
        controller.attach(canvas.firstView)
        scroll.horizontalRulerView?.clientView = canvas.firstView
        controller.refreshTrackChangeDisplay()
        canvas.configure(
            printLayout: printLayout,
            documentLength:
                document.text.length,
settings: document.metadata.page,
                sections: document.metadata.sections, zoom: controller.zoom, viewportWidth: scroll.contentSize.width)
        canvas.onFloatingImagesChange = { [weak controller, weak document] images, actionName in
            guard let controller, let document else { return false }
            return controller.setFloatingImages(images, in: document, actionName: actionName)
        }
        canvas.onSelectFloatingImage = { [weak controller] in controller?.selectedFloatingImageID = $0 }
        canvas.setFloatingImages(document.metadata.floatingImages ?? [])
        canvas.selectFloatingImage(controller.selectedFloatingImageID)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard
            let canvas =
                scroll.documentView
                    as? PaginatedEditor
        else {
            return
        }

        canvas.onFloatingImagesChange = { [weak controller, weak document] images, actionName in
            guard let controller, let document else { return false }
            return controller.setFloatingImages(images, in: document, actionName: actionName)
        }
        canvas.onSelectFloatingImage = { [weak controller] in controller?.selectedFloatingImageID = $0 }
        canvas.setFloatingImages(document.metadata.floatingImages ?? [])
        canvas.selectFloatingImage(controller.selectedFloatingImageID)

        for page in canvas.pages {
            page.importManuscript = onImportManuscript
            page.contextInsertLink = onContextLink
            page.contextAddComment = onContextComment
            page.contextSuggestEdits = onContextSuggest
            page.contextShowSpelling = onContextSpelling
        }
        scroll.hasHorizontalRuler = showRuler
        scroll.rulersVisible = showRuler
        scroll.horizontalRulerView?.clientView = (controller.textView as? WritingTextView) ?? canvas.firstView

        canvas.setEditingEnabled(
            editingEnabled
        )

        canvas.setShowsInvisibleCharacters(
            showNonPrintingCharacters
        )

        canvas.setShowsLineNumbers(
            showLineNumbers
        )

        let activeView =
            (controller.textView
                as? WritingTextView)
                .flatMap { candidate in
                    canvas.pages.contains(
                        where: {
                            $0 === candidate
                        }
                    )
                        ? candidate
                        : nil
                }
                ?? canvas.firstView

        let selected =
            activeView.selectedRange()

        let documentRevisionChanged =
            context.coordinator
                .lastAppliedRevisionID
                != document.revisionID

        if documentRevisionChanged,
           !canvas.firstView
                .attributedString()
                .isEqual(to: document.text) {

            context.coordinator
                .isApplyingDocument = true

            canvas.firstView
                .textStorage?
                .setAttributedString(
                    document.text
                )

            let location =
                min(
                    selected.location,
                    document.text.length
                )

            let length =
                min(
                    selected.length,
                    document.text.length
                        - location
                )

            let safeSelection =
                NSRange(
                    location: location,
                    length: length
                )

            if document.manuscriptReplacementRevisionID != document.revisionID {
                canvas.firstView.undoManager?.removeAllActions()
            }

            canvas.configure(
                printLayout: printLayout,
                documentLength:
                    document.text.length,
settings:
                    document.metadata.page,
                sections: document.metadata.sections,
                zoom: controller.zoom,
                viewportWidth:
                    scroll.contentSize.width
            )

            let restoredView =
                canvas.pageView(
                    containing:
                        safeSelection.location
                )

            restoredView.setSelectedRange(
                safeSelection
            )

            controller.attach(
                restoredView
            )

            controller
                .refreshTrackChangeDisplay()

            context.coordinator
                .lastAppliedRevisionID =
                    document.revisionID

            context.coordinator
                .isApplyingDocument = false

            return
        }

        if documentRevisionChanged {
            context.coordinator
                .lastAppliedRevisionID =
                    document.revisionID
        }

        let previousPrintLayout =
            canvas.printLayout

        let previousGeometry =
            canvas.geometry?.settings

        canvas.configure(
            printLayout: printLayout,
            documentLength:
                document.text.length,
settings:
                document.metadata.page,
                sections: document.metadata.sections,
            zoom: controller.zoom,
            viewportWidth:
                scroll.contentSize.width
        )

        let layoutModeChanged =
            previousPrintLayout
                != canvas.printLayout

        let pageSettingsChanged =
            printLayout
                && previousGeometry
                    != canvas.geometry?.settings

        let activeViewWasRemoved =
            !canvas.pages.contains(
                where: {
                    $0 === activeView
                }
            )

        if layoutModeChanged
            || pageSettingsChanged
            || activeViewWasRemoved {

            let location =
                min(
                    selected.location,
                    canvas.flow.storage.length
                )

            let length =
                min(
                    selected.length,
                    canvas.flow.storage.length
                        - location
                )

            let safeSelection =
                NSRange(
                    location: location,
                    length: length
                )

            let destination =
                canvas.pageView(
                    containing:
                        safeSelection.location
                )

            destination.setSelectedRange(
                safeSelection
            )

            controller.attach(
                destination
            )
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: BOLDWriterDocument
        let controller: EditorController
        var isApplyingDocument = false
        var isEditing = false
        var lastAppliedRevisionID: UUID?
        weak var canvas: PaginatedEditor?

        init(document: BOLDWriterDocument, controller: EditorController) {
            self.document = document
            self.controller = controller
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            controller.attach(textView)
            return controller.activateLink(link,in:document)
        }

        private func configureTrackedPaste(
            on textView: NSTextView
        ) {
            guard
                let writingView =
                    textView as? WritingTextView
            else {
                return
            }

            MainActor.assumeIsolated {
                controller.trackChangesProvider = {
                    [weak self] in

                    self?.document
                        .metadata
                        .trackChangesEnabled
                        ?? false
                }
            }

            writingView.trackChangesProvider = {
                [weak self] in

                self?.document
                    .metadata
                    .trackChangesEnabled
                    ?? false
            }

            writingView.trackAttributedPaste = {
                [weak self, weak writingView]
                replacement,
                range in

                MainActor.assumeIsolated {
                    guard
                        let self,
                        let writingView,
                        self.document
                            .metadata
                            .trackChangesEnabled
                            ?? false
                    else {
                        return false
                    }

                    self.controller.attach(
                        writingView
                    )

                    let handled =
                        self.controller
                            .trackAttributedPaste(
                                range:
                                    range,
                                replacement:
                                    replacement
                            )

                    self.controller.attach(
                        writingView
                    )

                    return handled
                }
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true

            if let textView =
                notification.object as? NSTextView {
                configureTrackedPaste(
                    on:
                        textView
                )

                controller.attach(textView)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            configureTrackedPaste(
                on:
                    textView
            )

            controller.attach(textView)
            controller.clearFootnoteTypingAttributes()
            controller.clearEndnoteTypingAttributes()
            guard let replacementString, affectedCharRange.location != NSNotFound else { return true }
            let safe = NoteReferences.editingRange(
                affectedCharRange,
                in: textView.attributedString()
            )

            let replacement =
                NSAttributedString(
                    string: replacementString,
                    attributes: textView.typingAttributes
                )

            // Keep table structural protection authoritative.
            // Table editing remains on its proven snapshot path.
            if controller.handleTableEdit(
                range: safe,
                replacement: replacement,
                trackChanges:
                    document.metadata
                        .trackChangesEnabled
                        ?? false
            ) {
                controller.attach(textView)
                return false
            }

            // Footnote-marker expansion also retains its existing
            // protected replacement behavior.
            if safe != affectedCharRange {
                controller.replace(
                    range: safe,
                    with: replacement,
                    actionName: "Edit Text",
                    trackChanges:
                        document.metadata
                            .trackChangesEnabled
                            ?? false
                )
                controller.attach(textView)
                return false
            }

            if document.metadata.trackChangesEnabled ?? false {
                let handled =
                    controller.trackTextEdit(
                        range: safe,
                        replacement: replacement
                    )

                // A tracked mutation can synchronously emit TextKit editing
                // notifications while pagination is invalidating downstream
                // pages. The command still belongs to the physical page that
                // initiated it, so restore that active page explicitly.
                controller.attach(textView)

                return !handled
            }

            controller.attach(textView)
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertTab(_:)) { return controller.navigateTable(forward: true) }
            if commandSelector == #selector(NSTextView.insertBacktab(_:)) { return controller.navigateTable(forward: false) }
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingDocument, let textView = notification.object as? NSTextView else { return }
            controller.attach(textView)
            controller.normalizeFootnotes()
            controller.normalizeEndnotes()
            controller.clearFootnoteTypingAttributes()
            controller.clearEndnoteTypingAttributes()
            document.replaceEditedText(
                with:
                    textView.attributedString()
            )

            lastAppliedRevisionID =
                document.revisionID

            controller.updateSelection(textView.selectedRange())
            controller.refreshTrackChangeDisplay()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            configureTrackedPaste(
                on:
                    textView
            )

            controller.selectedReviewChangeID = nil
            controller.attach(textView)
            controller.clearFootnoteTypingAttributes()
            controller.clearEndnoteTypingAttributes()
            controller.updateTableTypingAttributes()
        }
    }
}

/// A view onto the shared text network. Continuous mode reflows to the viewport;
/// page mode retains finite physical-point geometry regardless of visual zoom.

enum BOLDDocumentDropRouter {
    static let documentFileExtensions:
        Set<String> =
        [
            "boldwriter",
            "docx",
            "doc",
            "rtf",
            "rtfd",
            "txt",
            "md",
            "markdown",
            "html",
            "htm",
            "pdf"
        ]

    static func shouldOpenAsDocument(
        _ url: URL
    ) -> Bool {
        guard
            url.isFileURL
        else {
            return false
        }

        return documentFileExtensions
            .contains(
                url.pathExtension
                    .lowercased()
            )
    }

    static func documentURLs(
        from pasteboard:
            NSPasteboard
    ) -> [URL] {
        let objects =
            pasteboard.readObjects(
                forClasses:
                    [
                        NSURL.self
                    ],
                options:
                    [
                        .urlReadingFileURLsOnly:
                            true
                    ]
            )
            ?? []

        return objects
            .compactMap {
                if let value =
                    $0 as? URL
                {
                    return value
                }

                if let value =
                    $0 as? NSURL
                {
                    return value
                        as URL
                }

                return nil
            }
            .filter(
                shouldOpenAsDocument
            )
    }

    static func openDocuments(
        _ urls: [URL]
    ) {
        guard
            !urls.isEmpty
        else {
            return
        }

        DispatchQueue.main.async {
            for url in urls {
                NSDocumentController
                    .shared
                    .openDocument(
                        withContentsOf:
                            url,
                        display:
                            true
                    ) {
                        _,
                        _,
                        error
                        in

                        if let error {
                            NSApp.presentError(
                                error
                            )
                        }
                    }
            }
        }
    }
}

final class WritingTextView: NSTextView {
    private func boldDocumentURLs(
        from draggingInfo:
            NSDraggingInfo
    ) -> [URL] {
        BOLDDocumentDropRouter
            .documentURLs(
                from:
                    draggingInfo
                        .draggingPasteboard
            )
    }

    override func draggingEntered(
        _ sender:
            NSDraggingInfo
    ) -> NSDragOperation {
        if !boldDocumentURLs(
            from:
                sender
        )
        .isEmpty {
            return .copy
        }

        return super.draggingEntered(
            sender
        )
    }

    override func draggingUpdated(
        _ sender:
            NSDraggingInfo
    ) -> NSDragOperation {
        if !boldDocumentURLs(
            from:
                sender
        )
        .isEmpty {
            return .copy
        }

        return super.draggingUpdated(
            sender
        )
    }

    override func prepareForDragOperation(
        _ sender:
            NSDraggingInfo
    ) -> Bool {
        if !boldDocumentURLs(
            from:
                sender
        )
        .isEmpty {
            return true
        }

        return super.prepareForDragOperation(
            sender
        )
    }

    override func performDragOperation(
        _ sender:
            NSDraggingInfo
    ) -> Bool {
        let documentURLs =
            boldDocumentURLs(
                from:
                    sender
            )

        guard
            !documentURLs.isEmpty
        else {
            return super.performDragOperation(
                sender
            )
        }

        if documentURLs.count == 1, let url = documentURLs.first,
           url.pathExtension.lowercased() == "docx", let importManuscript {
            importManuscript(url)
            return true
        }
        BOLDDocumentDropRouter
            .openDocuments(
                documentURLs
            )

        return true
    }


    var importManuscript: ((URL) -> Void)?
    weak var floatingImageCanvas: PaginatedEditor?
    var sessionUndoManager: UndoManager?

    var trackChangesProvider:
        (@MainActor () -> Bool)?

    var trackAttributedPaste:
        (@MainActor (NSAttributedString, NSRange) -> Bool)?

    override var undoManager: UndoManager? {
        sessionUndoManager
            ?? super.undoManager
    }
    var pageGeometry: PageGeometry? {
        didSet {
            updateWritingGeometry()
        }
    }

    var pageNumber = 1
    var sectionPageNumber = 1
    var displayPageNumber = 1

    var drawsPageFurniture =
        true

    var showsLineNumbers = false {
        didSet {
            if oldValue != showsLineNumbers {
                needsDisplay = true
            }
        }
    }

    var pageFootnotes = PageFootnotePlan() {
        didSet { needsDisplay = true }
    }
    var reservedFootnoteHeight: CGFloat = 0

    var writingContentSizeOverride:
        NSSize? {
        didSet {
            updateWritingGeometry()
        }
    }

    var writingOriginOverride:
        NSPoint? {
        didSet {
            updateWritingGeometry()
        }
    }

    override func draw(
        _ dirtyRect: NSRect
    ) {
        floatingImageCanvas?.drawFloatingImages(in: self, layer: .behindText, dirtyRect: dirtyRect)
        super.draw(
            dirtyRect
        )

        floatingImageCanvas?.drawFloatingImages(in: self, layer: .inFrontOfText, dirtyRect: dirtyRect)
        floatingImageCanvas?.drawFloatingImageSelection(in: self)

        drawLineNumbers(
            in:
                dirtyRect
        )

        if drawsPageFurniture {
            if let pageGeometry {
                PageFootnotes.draw(pageFootnotes, in: pageGeometry)
            }
            pageGeometry?
                .drawFooter(
                    page:
                        pageNumber,
                    sectionPage:
                        sectionPageNumber,
                    displayPage:
                        displayPageNumber
                )
        }
    }


    private func drawLineNumbers(
        in dirtyRect: NSRect
    ) {
        guard
            showsLineNumbers,
            let layoutManager,
            let textContainer
        else {
            return
        }

        let glyphRange =
            layoutManager.glyphRange(
                for:
                    textContainer
            )

        guard
            glyphRange.location != NSNotFound,
            glyphRange.length > 0
        else {
            return
        }

        var lineNumber = 1

        if glyphRange.location > 0 {
            layoutManager.enumerateLineFragments(
                forGlyphRange:
                    NSRange(
                        location:
                            0,
                        length:
                            glyphRange.location
                    )
            ) {
                _,
                _,
                _,
                _,
                _ in

                lineNumber += 1
            }
        }

        let font =
            NSFont.monospacedDigitSystemFont(
                ofSize:
                    9,
                weight:
                    .regular
            )

        let attributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    font,
                .foregroundColor:
                    NSColor.secondaryLabelColor
            ]

        let origin =
            textContainerOrigin

        let gutterWidth:
            CGFloat =
                34

        let gutterX =
            max(
                2,
                origin.x
                    - gutterWidth
                    - 6
            )

        let storage =
            attributedString()

        layoutManager.enumerateLineFragments(
            forGlyphRange:
                glyphRange
        ) {
            _,
            usedRect,
            _,
            fragmentGlyphRange,
            _ in

            defer {
                lineNumber += 1
            }

            let characterRange =
                layoutManager.characterRange(
                    forGlyphRange:
                        fragmentGlyphRange,
                    actualGlyphRange:
                        nil
                )

            guard
                characterRange.location != NSNotFound,
                characterRange.location < storage.length
            else {
                return
            }

            let suppress =
                storage.attribute(
                    .boldWriterSuppressLineNumbers,
                    at:
                        characterRange.location,
                    effectiveRange:
                        nil
                )
                as? Bool
                ?? false

            guard !suppress else {
                return
            }

            let y =
                origin.y
                + usedRect.minY

            let value =
                String(lineNumber)
                as NSString

            let size =
                value.size(
                    withAttributes:
                        attributes
                )

            let rect =
                NSRect(
                    x:
                        gutterX,
                    y:
                        y,
                    width:
                        gutterWidth,
                    height:
                        max(
                            usedRect.height,
                            size.height
                        )
                )

            guard
                rect.intersects(
                    dirtyRect
                )
            else {
                return
            }

            value.draw(
                at:
                    NSPoint(
                        x:
                            rect.maxX
                            - size.width,
                        y:
                            y
                            + max(
                                0,
                                (
                                    usedRect.height
                                    - size.height
                                )
                                / 2
                            )
                    ),
                withAttributes:
                    attributes
            )
        }
    }

    weak var tableController: EditorController?
    var editFootnote: (() -> Void)?

    var editEndnote: (() -> Void)?
    var contextInsertLink: (() -> Void)?
    var contextAddComment: (() -> Void)?
    var contextSuggestEdits: (() -> Void)?
    var contextShowSpelling: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hasSelection = selectedRange().length > 0
        let editable = isEditable
        let canPaste = NSPasteboard.general.availableType(from: [
            .string, .rtf, .html, .tiff, .png, Tables.pasteboardType
        ]) != nil

        func item(_ title: String, action: Selector, enabled: Bool, shortcut: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            entry.target = self
            entry.isEnabled = enabled
            menu.addItem(entry)
        }

        item("Cut", action: #selector(cut(_:)), enabled: editable && hasSelection, shortcut: "x")
        item("Copy", action: #selector(copy(_:)), enabled: hasSelection, shortcut: "c")
        item("Paste", action: #selector(paste(_:)), enabled: editable && canPaste, shortcut: "v")
        item("Paste Without Formatting", action: #selector(pasteWithoutFormatting(_:)),
             enabled: editable && NSPasteboard.general.string(forType: .string) != nil)
        item("Delete", action: #selector(deleteBackward(_:)), enabled: editable && hasSelection)
        menu.addItem(.separator())
        item("Add Comment…", action: #selector(contextComment(_:)), enabled: editable && contextAddComment != nil)
        item("Suggest Edits", action: #selector(contextSuggest(_:)), enabled: editable && contextSuggestEdits != nil)
        item("Insert Link…", action: #selector(contextLink(_:)), enabled: editable && contextInsertLink != nil)
        menu.addItem(.separator())
        item("Spelling and Grammar…", action: #selector(contextSpelling(_:)), enabled: contextShowSpelling != nil)
        item("Clear Formatting", action: #selector(contextClearFormatting(_:)), enabled: editable && tableController != nil)
        return menu
    }

    @objc private func contextLink(_ sender: Any?) { contextInsertLink?() }
    @objc private func contextComment(_ sender: Any?) { contextAddComment?() }
    @objc private func contextSuggest(_ sender: Any?) { contextSuggestEdits?() }
    @objc private func contextSpelling(_ sender: Any?) { contextShowSpelling?() }
    @objc private func contextClearFormatting(_ sender: Any?) { tableController?.clearDirectFormatting() }
    /// Resolve the source-side operation mask for text dragging.
    ///
    /// A native internal NSTextView drag normally permits MOVE.
    /// AppKit then owns the source deletion after the destination
    /// accepts the drop. That source-side deletion does not expose a
    /// reliable attributed replacement callback that BOLD can safely
    /// convert into a tracked deletion.
    ///
    /// Therefore Track Changes deliberately makes drag operations
    /// copy-only. The destination insertion is still routed through
    /// readSelection(from:type:) and becomes a normal reviewable
    /// insertion, while the source text remains untouched.
    func constrainedDragSourceOperationMask(
        _ nativeMask: NSDragOperation
    ) -> NSDragOperation {
        guard
            trackChangesProvider?()
                ?? false
        else {
            return nativeMask
        }

        return .copy
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        let nativeMask =
            super.draggingSession(
                session,
                sourceOperationMaskFor:
                    context
            )

        return constrainedDragSourceOperationMask(
            nativeMask
        )
    }

    override func copy(_ sender: Any?) {
        super.copy(sender)
        let selection = selectedRange()
        guard selection.location != NSNotFound, selection.length > 0,
              let data = try? Tables.clipboardData(attributedString().attributedSubstring(from: selection)) else { return }
        NSPasteboard.general.addTypes([Tables.pasteboardType], owner: nil)
        NSPasteboard.general.setData(data, forType: Tables.pasteboardType)
    }

    override func cut(_ sender: Any?) {
        let tracking =
            trackChangesProvider?()
            ?? false

        guard
            tracking,
            let controller =
                tableController
        else {
            super.cut(sender)
            return
        }

        let selection =
            selectedRange()

        guard
            selection.location
                != NSNotFound,
            selection.length > 0
        else {
            super.cut(sender)
            return
        }

        // Footnote references are atomic editing units. Expand the
        // selection before copying so the clipboard and tracked
        // deletion describe the same content.
        let safeRange =
            NoteReferences.editingRange(
                selection,
                in:
                    attributedString()
            )

        if safeRange
            != selection {

            setSelectedRange(
                safeRange
            )
        }

        // Cut must still populate the system clipboard normally,
        // including BOLD's structured-table payload when a complete
        // table is selected.
        copy(sender)

        controller.attach(
            self
        )

        // Do not let AppKit physically remove the selection while
        // Track Changes is enabled. Route the deletion through the
        // same protected programmatic replacement path used by AI,
        // Find/Replace, footnotes, and tables.
        controller.replace(
            range:
                safeRange,
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Cut",
            trackChanges:
                true
        )

        controller.attach(
            self
        )
    }

    @objc func pasteWithoutFormatting(_ sender: Any?) {
        guard
            let string =
                NSPasteboard.general.string(
                    forType:
                        .string
                )
        else {
            NSSound.beep()
            return
        }

        let tracking =
            trackChangesProvider?()
            ?? false

        let replacement =
            NSAttributedString(
                string:
                    string,
                attributes:
                    typingAttributes
            )

        if tracking,
           trackAttributedPaste?(
                replacement,
                selectedRange()
           ) == true {
            return
        }

        if let controller =
            tableController,
           controller.handleTableEdit(
                range:
                    selectedRange(),
                replacement:
                    replacement,
                trackChanges:
                    tracking
           ) {
            return
        }

        insertText(
            replacement,
            replacementRange:
                selectedRange()
        )
    }

    override func paste(_ sender: Any?) {
        let tracking =
            trackChangesProvider?()
            ?? false

        if let controller = tableController,
           let data =
            NSPasteboard.general
                .data(
                    forType:
                        Tables.pasteboardType
                ),
           controller.pasteTables(
                data,
                trackChanges:
                    tracking
           ) {
            return
        }

        if tracking,
           let replacement =
            pasteboardAttributedContent(
                from:
                    NSPasteboard.general
            ),
           trackAttributedPaste?(
                replacement,
                selectedRange()
           ) == true {
            return
        }

        if let controller = tableController,
           let string =
            NSPasteboard.general
                .string(
                    forType:
                        .string
                ),
           controller.handleTableEdit(
                range:
                    selectedRange(),
                replacement:
                    NSAttributedString(
                        string:
                            string,
                        attributes:
                            typingAttributes
                    ),
                trackChanges:
                    tracking
           ) {
            return
        }

        super.paste(sender)
    }

    /// NSTextView uses readSelection(from:type:) for more than
    /// Command-V paste. Drag/drop and other pasteboard-driven edits
    /// can arrive here without a plain replacementString, so the
    /// delegate alone cannot safely create a tracked revision.
    ///
    /// While Track Changes is enabled, never allow compatible
    /// pasteboard content to fall through to an untracked native
    /// insertion. Route rich text, images, plain text, and BOLD
    /// structured tables through the same revision machinery as
    /// Paste.
    override func readSelection(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType
    ) -> Bool {
        let tracking =
            trackChangesProvider?()
            ?? false

        guard tracking else {
            return super.readSelection(
                from:
                    pasteboard,
                type:
                    type
            )
        }

        if let controller =
            tableController,
           let data =
            pasteboard.data(
                forType:
                    Tables.pasteboardType
            ),
           controller.pasteTables(
                data,
                trackChanges:
                    true
           ) {

            return true
        }

        if let replacement =
            pasteboardAttributedContent(
                from:
                    pasteboard
            ),
           trackAttributedPaste?(
                replacement,
                selectedRange()
           ) == true {

            return true
        }

        // Silently falling through here would permit AppKit to
        // insert content without a revision marker. Blocking an
        // unsupported drop while tracking is safer than allowing
        // an invisible bypass.
        NSSound.beep()

        return false
    }

    private func pasteboardAttributedContent(
        from pasteboard: NSPasteboard
    ) -> NSAttributedString? {

        if let data =
            pasteboard.data(
                forType:
                    .rtfd
            ),
           let value =
            try? NSAttributedString(
                data:
                    data,
                options: [
                    .documentType:
                        NSAttributedString
                            .DocumentType
                            .rtfd
                ],
                documentAttributes:
                    nil
            ) {
            return value
        }

        if let data =
            pasteboard.data(
                forType:
                    .rtf
            ),
           let value =
            try? NSAttributedString(
                data:
                    data,
                options: [
                    .documentType:
                        NSAttributedString
                            .DocumentType
                            .rtf
                ],
                documentAttributes:
                    nil
            ) {
            return value
        }

        if let image =
            NSImage(
                pasteboard:
                    pasteboard
            ) {
            let attachment =
                NSTextAttachment()

            attachment.image =
                image

            if image.size.width > 0,
               image.size.height > 0 {
                attachment.bounds =
                    NSRect(
                        origin:
                            .zero,
                        size:
                            image.size
                    )
            }

            return NSAttributedString(
                attachment:
                    attachment
            )
        }

        if let string =
            pasteboard.string(
                forType:
                    .string
            ) {
            return NSAttributedString(
                string:
                    string,
                attributes:
                    typingAttributes
            )
        }

        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if floatingImageCanvas?.handleFloatingImageMouseDown(event, in: self) == true { return }
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }

        super.mouseDown(with: event)

        if event.clickCount == 2, let notes = try? Footnotes.records(in: attributedString()) {
            let point = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if let note = notes.first(where: { point >= $0.location && point <= $0.location + $0.length }) {
                setSelectedRange(NSRange(location: note.location, length: note.length))
                editFootnote?()
            }
        }

        if event.clickCount == 2, let notes = try? Endnotes.records(in: attributedString()) {
            let point = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if let note = notes.first(where: { point >= $0.location && point <= $0.location + $0.length }) {
                setSelectedRange(NSRange(location: note.location, length: note.length))
                editEndnote?()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if floatingImageCanvas?.handleFloatingImageKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    var writingMargins = NSEdgeInsets(top: 42, left: 52, bottom: 42, right: 52) {
        didSet { updateWritingGeometry() }
    }

    override var textContainerOrigin: NSPoint {
        writingOriginOverride
            ?? NSPoint(
                x:
                    writingMargins.left,
                y:
                    writingMargins.top
            )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateWritingGeometry()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateWritingGeometry()
    }

    private func updateWritingGeometry() {
        guard let textContainer else { return }
        textContainer.widthTracksTextView = false
        let inset = NSSize(width: 0, height: max(writingMargins.top, writingMargins.bottom))
        if textContainerInset != inset { textContainerInset = inset }
        let size =
            writingContentSizeOverride
            ?? pageGeometry?.contentSize
            ?? NSSize(
                width:
                    max(
                        1,
                        bounds.width
                            - writingMargins.left
                            - writingMargins.right
                    ),
                height:
                    CGFloat
                        .greatestFiniteMagnitude
            )

        textContainer.heightTracksTextView =
            false

        if textContainer.containerSize
            != size {

            textContainer.containerSize =
                size
        }
    }
}


@MainActor
private final class EditorScrollView: NSScrollView {
    override func tile() {
        super.tile()
        (documentView as? PaginatedEditor)?.viewportChanged(width: contentSize.width)
    }
}
