import AppKit
import PDFKit
import SwiftUI
import XCTest
@testable import BOLDWriter

@MainActor
final class WritingInterfaceTests: XCTestCase {
    func testEditorRulerUsesNativeTextViewAndRespondsToVisibilityToggle() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "A paragraph with a tab\tstop."))
        let controller = EditorController()
        let host = NSHostingView(rootView: RichTextEditor(
            document: document, controller: controller, printLayout: true, showRuler: true
        ))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        host.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(controller.textView)
        let scroll = try XCTUnwrap(textView.enclosingScrollView)
        XCTAssertTrue(scroll.hasHorizontalRuler)
        XCTAssertTrue(scroll.rulersVisible)
        XCTAssertTrue(scroll.horizontalRulerView?.clientView === textView)

        host.rootView = RichTextEditor(document: document, controller: controller, printLayout: true, showRuler: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(scroll.rulersVisible)
    }

    func testTextReflowsAcrossSidebarWidthsAndZoomWithoutChangingContent() throws {
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 510, height: 600))
        view.writingMargins = NSEdgeInsets(top: 72, left: 54, bottom: 72, right: 90)
        let original = NSAttributedString(string: String(repeating: "Readable manuscript text with wrapping. ", count: 80),
                                          attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor])
        view.textStorage?.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 12, length: 8))
        for width in [510.0, 750, 1052, 1500, 510] {
            view.setFrameSize(NSSize(width: width, height: 600))
            for zoom in [0.65, 1.0, 1.8] {
                view.setBoundsSize(NSSize(width: width / zoom, height: 600 / zoom))
                let container = try XCTUnwrap(view.textContainer)
                let layout = try XCTUnwrap(view.layoutManager)
                layout.ensureLayout(for: container)
                XCTAssertEqual(container.containerSize.width, width / zoom - 144, accuracy: 0.01)
                XCTAssertLessThanOrEqual(layout.usedRect(for: container).maxX, container.containerSize.width + 0.01)
                XCTAssertEqual(view.textContainerOrigin.x, 54)
                XCTAssertTrue(original.isEqual(to: view.attributedString()))
                XCTAssertEqual(view.selectedRange(), NSRange(location: 12, length: 8))
            }
        }
    }

    func testPrintPaperStaysLightInsideDarkWindowWithoutRecoloringDocument() throws {
        let document = BOLDWriterDocument()
        let original = NSAttributedString(string: "Paper text", attributes: [.foregroundColor: NSColor.textColor])
        document.replaceText(with: original)
        let controller = EditorController()
        let host = NSHostingView(rootView: RichTextEditor(document: document, controller: controller, printLayout: true))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(controller.textView)
        XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        XCTAssertEqual(view.backgroundColor, .white)
        XCTAssertFalse(view.usesAdaptiveColorMappingForDarkAppearance)
        XCTAssertTrue(original.isEqual(to: document.text))

        // NSTextView is allowed to supply a default display font when the
        // source attributed string intentionally contains no font attribute.
        // What Print Layout must never do is alter the manuscript text,
        // recolor it, or write those presentation defaults back to the document.
        let displayed = view.attributedString()
        XCTAssertEqual(displayed.string, original.string)

        let originalColor = original.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        let displayedColor = displayed.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        XCTAssertEqual(displayedColor, originalColor)

        host.rootView = RichTextEditor(document: document, controller: controller, printLayout: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertNil(view.appearance)
        XCTAssertTrue(view.usesAdaptiveColorMappingForDarkAppearance)
        XCTAssertTrue(original.isEqual(to: document.text))
    }
    func testPrintLayoutPageCountMatchesPDFExporter()
        throws {
        var settings = PageSettings()
        settings.topMargin = 72
        settings.bottomMargin = 72
        settings.leftMargin = 72
        settings.rightMargin = 72

        let paragraph =
            "A substantial manuscript paragraph intended to exercise real pagination, line wrapping, and page flow across multiple finite TextKit containers. "

        let value =
            Array(
                repeating:
                    paragraph
                    + paragraph
                    + paragraph
                    + "\n",
                count: 80
            )
            .joined()

        let text =
            NSAttributedString(
                string: value,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        ),
                    .foregroundColor:
                        NSColor.textColor
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertGreaterThan(
            editor.pages.count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            editor.pages.count
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from: text,
                            settings: settings
                        )
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            pdf.pageCount
        )

        XCTAssertEqual(
            editor.pageRanges.first?.location,
            0
        )

        XCTAssertEqual(
            editor.pageRanges.last.map(
                NSMaxRange
            ),
            text.length
        )

        for index in
            1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index].location,
                NSMaxRange(
                    editor.pageRanges[index - 1]
                )
            )
        }
    }

    func testTerminalPageBreakCreatesRealEmptyFinalPage()
        throws {
        let settings =
            PageSettings()

        let text =
            NSAttributedString(
                string:
                    "Content before the final page break.\u{000C}",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges[0].location,
            0
        )

        XCTAssertEqual(
            NSMaxRange(
                editor.pageRanges[0]
            ),
            text.length
        )

        XCTAssertEqual(
            editor.pageRanges[1],
            NSRange(
                location: text.length,
                length: 0
            )
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from: text,
                            settings: settings
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            2
        )
    }

    func testPrintPaginationIsIndependentOfZoomAndViewportWidth()
        throws {
        var settings =
            PageSettings()

        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 63
        settings.rightMargin = 63

        let value =
            Array(
                repeating:
                    "Physical page geometry must remain stable when only the visual zoom or editor viewport changes. This protects Word-style page boundaries while the user zooms or opens sidebars.\n",
                count: 140
            )
            .joined()

        let text =
            NSAttributedString(
                string: value,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 14
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        let originalCount =
            editor.pages.count

        let originalRanges =
            editor.pageRanges

        XCTAssertGreaterThan(
            originalCount,
            1
        )

        for configuration in [
            (0.65, CGFloat(520)),
            (1.8, CGFloat(1600)),
            (1.25, CGFloat(760)),
            (1.0, CGFloat(1000))
        ] {
            editor.configure(
                printLayout: true,
                settings: settings,
                zoom: configuration.0,
                viewportWidth:
                    configuration.1
            )

            editor.finishPagination()

            XCTAssertNil(
                editor.lastLayoutError
            )

            XCTAssertEqual(
                editor.pages.count,
                originalCount
            )

            XCTAssertEqual(
                editor.pageRanges,
                originalRanges
            )
        }
    }



    func testPaginationRepaginatesAfterLargeInsertion()
        throws {
        let settings =
            PageSettings()

        let original =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Initial manuscript paragraph with enough text to create several physical pages in Print Layout.\n",
                        count: 120
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 14
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: original
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        let originalPageCount =
            editor.pages.count

        XCTAssertGreaterThan(
            originalPageCount,
            1
        )

        let added =
            Array(
                repeating:
                    "Inserted material that must force TextKit to repaginate every affected downstream page while preserving one shared manuscript storage.\n",
                count: 220
            )
            .joined()

        editor.flow.storage.replaceCharacters(
            in: NSRange(
                location: 0,
                length: 0
            ),
            with: added
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThan(
            editor.pages.count,
            originalPageCount
        )

        XCTAssertEqual(
            editor.pages.count,
            editor.pageRanges.count
        )

        XCTAssertEqual(
            editor.pageRanges.first?.location,
            0
        )

        XCTAssertEqual(
            editor.pageRanges.last.map(
                NSMaxRange
            ),
            editor.flow.storage.length
        )

        for index in
            1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index].location,
                NSMaxRange(
                    editor.pageRanges[index - 1]
                )
            )
        }

        let current =
            NSAttributedString(
                attributedString:
                    editor.flow.storage
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from: current,
                            settings: settings
                        )
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            pdf.pageCount
        )

        XCTAssertEqual(
            current.string,
            added + original.string
        )
    }

    func testPaginationShrinksAndRemovesStalePagesAfterLargeDeletion()
        throws {
        let settings =
            PageSettings()

        let value =
            Array(
                repeating:
                    "Long manuscript content used to verify that deleting most of a document removes stale page views and produces the same final pagination as PDF export.\n",
                count: 360
            )
            .joined()

        let original =
            NSAttributedString(
                string: value,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 14
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: original
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        let originalPageCount =
            editor.pages.count

        XCTAssertGreaterThan(
            originalPageCount,
            2
        )

        let keepLength =
            min(
                900,
                editor.flow.storage.length
            )

        editor.flow.storage.deleteCharacters(
            in: NSRange(
                location: keepLength,
                length:
                    editor.flow.storage.length
                    - keepLength
            )
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertLessThan(
            editor.pages.count,
            originalPageCount
        )

        XCTAssertEqual(
            editor.pages.count,
            editor.pageRanges.count
        )

        XCTAssertEqual(
            editor.pageRanges.first?.location,
            0
        )

        XCTAssertEqual(
            editor.pageRanges.last.map(
                NSMaxRange
            ),
            editor.flow.storage.length
        )

        for index in
            1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index].location,
                NSMaxRange(
                    editor.pageRanges[index - 1]
                )
            )
        }

        let current =
            NSAttributedString(
                attributedString:
                    editor.flow.storage
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from: current,
                            settings: settings
                        )
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            pdf.pageCount
        )

        XCTAssertEqual(
            current.length,
            keepLength
        )
    }



    func testControllerFollowsActivePaginatedTextView()
        throws {
        let document =
            BOLDWriterDocument()

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Editable manuscript content flowing across physical pages in Print Layout.\n",
                        count: 180
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let coordinator =
            RichTextEditor.Coordinator(
                document: document,
                controller: controller
            )

        let canvas =
            PaginatedEditor(
                text: text
            )

        coordinator.canvas = canvas

        canvas.configureTextView = {
            textView in

            textView.delegate =
                coordinator
        }

        canvas.configureTextView?(
            canvas.firstView
        )

        controller.attach(
            canvas.firstView
        )

        canvas.configure(
            printLayout: true,
            settings: document.metadata.page,
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondPage =
            canvas.pages[1]

        let secondRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst()
                    .first {
                        $0.length > 4
                    }
            )

        let selection =
            NSRange(
                location:
                    secondRange.location,
                length: 4
            )

        secondPage.setSelectedRange(
            selection
        )

        coordinator
            .textViewDidChangeSelection(
                Notification(
                    name:
                        NSTextView
                            .didChangeSelectionNotification,
                    object: secondPage
                )
            )

        XCTAssertTrue(
            controller.textView
                === secondPage
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        controller.setFontSize(
            26
        )

        let changedFont =
            try XCTUnwrap(
                canvas.flow.storage
                    .attribute(
                        .font,
                        at: selection.location,
                        effectiveRange: nil
                    )
                    as? NSFont
            )

        XCTAssertEqual(
            changedFont.pointSize,
            26,
            accuracy: 0.01
        )
    }

    func testSecondPageTypingRoutesThroughActiveController()
        throws {
        let document =
            BOLDWriterDocument()

        document.metadata
            .trackChangesEnabled = true

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Tracked manuscript text flowing through multiple physical page views.\n",
                        count: 180
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let coordinator =
            RichTextEditor.Coordinator(
                document: document,
                controller: controller
            )

        let canvas =
            PaginatedEditor(
                text: text
            )

        coordinator.canvas = canvas

        canvas.configureTextView = {
            textView in

            textView.delegate =
                coordinator
        }

        canvas.configureTextView?(
            canvas.firstView
        )

        controller.attach(
            canvas.firstView
        )

        canvas.configure(
            printLayout: true,
            settings: document.metadata.page,
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondPage =
            canvas.pages[1]

        let secondRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst()
                    .first {
                        $0.length > 0
                    }
            )

        let insertionPoint =
            secondRange.location

        secondPage.setSelectedRange(
            NSRange(
                location: insertionPoint,
                length: 0
            )
        )

        let allowNativeEdit =
            coordinator.textView(
                secondPage,
                shouldChangeTextIn:
                    NSRange(
                        location: insertionPoint,
                        length: 0
                    ),
                replacementString:
                    "X"
            )

        XCTAssertFalse(
            allowNativeEdit
        )

        XCTAssertTrue(
            controller.textView
                === secondPage
        )

        let records =
            TrackChanges.records(
                in: canvas.flow.storage
            )

        XCTAssertEqual(
            records.count,
            1
        )

        XCTAssertEqual(
            records.first?.kind,
            .insertion
        )

        XCTAssertEqual(
            records.first?.location,
            insertionPoint
        )

        XCTAssertEqual(
            records.first?.length,
            1
        )

        XCTAssertEqual(
            (canvas.flow.storage.string
                as NSString)
                .substring(
                    with:
                        NSRange(
                            location:
                                insertionPoint,
                            length: 1
                        )
                ),
            "X"
        )
    }



    func testDocumentUpdatePreservesActiveSecondPageSelection()
        throws {
        let document =
            BOLDWriterDocument()

        let original =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Document update cycle content flowing across multiple physical page views.\n",
                        count: 190
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: original
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        host.layoutSubtreeIfNeeded()

        let firstView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                firstView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst()
                    .first {
                        $0.length > 8
                    }
            )

        let secondPage =
            canvas.pageView(
                containing:
                    secondRange.location
            )

        let selection =
            NSRange(
                location:
                    secondRange.location + 2,
                length: 5
            )

        secondPage.setSelectedRange(
            selection
        )

        controller.attach(
            secondPage
        )

        XCTAssertTrue(
            controller.textView
                === secondPage
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        let changed =
            NSMutableAttributedString(
                attributedString:
                    original
            )

        changed.addAttribute(
            .backgroundColor,
            value:
                NSColor.systemYellow,
            range:
                NSRange(
                    location: 0,
                    length: 1
                )
        )

        document.replaceText(
            with: changed
        )

        host.rootView =
            RichTextEditor(
                document: document,
                controller: controller,
                printLayout: true
            )

        host.layoutSubtreeIfNeeded()

        let restoredView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let restoredCanvas =
            try XCTUnwrap(
                restoredView.superview
                    as? PaginatedEditor
            )

        restoredCanvas.finishPagination()

        let expectedPage =
            restoredCanvas.pageView(
                containing:
                    selection.location
            )

        XCTAssertTrue(
            controller.textView
                === expectedPage
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        XCTAssertEqual(
            expectedPage.selectedRange(),
            selection
        )

        XCTAssertEqual(
            restoredCanvas.flow.storage
                .attribute(
                    .backgroundColor,
                    at: 0,
                    effectiveRange: nil
                ) as? NSColor,
            NSColor.systemYellow
        )
    }



    func testNavigationMovesControllerToDestinationPage()
        throws {
        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Navigation manuscript content flowing across many physical Print Layout pages.\n",
                        count: 260
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let controller =
            EditorController()

        let canvas =
            PaginatedEditor(
                text: text
            )

        controller.attach(
            canvas.firstView
        )

        canvas.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertGreaterThanOrEqual(
            canvas.pages.count,
            3
        )

        let destinationRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst(2)
                    .first {
                        $0.length > 8
                    }
            )

        let target =
            NSRange(
                location:
                    destinationRange.location + 2,
                length: 5
            )

        controller.navigate(
            to: target
        )

        let expectedPage =
            canvas.pageView(
                containing:
                    target.location
            )

        XCTAssertTrue(
            controller.textView
                === expectedPage
        )

        XCTAssertEqual(
            controller.selection,
            target
        )

        XCTAssertEqual(
            expectedPage.selectedRange(),
            target
        )

        XCTAssertFalse(
            expectedPage
                === canvas.firstView
        )
    }

    func testNavigationBackAcrossPagesReattachesEarlierPage()
        throws {
        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Forward and backward navigation must always route toolbar commands to the physical page containing the selected result.\n",
                        count: 260
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let controller =
            EditorController()

        let canvas =
            PaginatedEditor(
                text: text
            )

        controller.attach(
            canvas.firstView
        )

        canvas.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertGreaterThanOrEqual(
            canvas.pages.count,
            3
        )

        let laterRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst(2)
                    .first {
                        $0.length > 4
                    }
            )

        controller.navigate(
            to:
                NSRange(
                    location:
                        laterRange.location + 1,
                    length: 3
                )
        )

        XCTAssertFalse(
            controller.textView
                === canvas.firstView
        )

        let firstRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .first {
                        $0.length > 8
                    }
            )

        let returnTarget =
            NSRange(
                location:
                    firstRange.location + 2,
                length: 4
            )

        controller.navigate(
            to: returnTarget
        )

        let expectedPage =
            canvas.pageView(
                containing:
                    returnTarget.location
            )

        XCTAssertTrue(
            controller.textView
                === expectedPage
        )

        XCTAssertTrue(
            expectedPage
                === canvas.firstView
        )

        XCTAssertEqual(
            controller.selection,
            returnTarget
        )

        XCTAssertEqual(
            expectedPage.selectedRange(),
            returnTarget
        )
    }



    func testExactPageBoundaryBelongsToFollowingPage()
        throws {
        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Page-boundary ownership must use half-open character ranges so a caret at the first character of a new page belongs to that new physical page.\n",
                        count: 220
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let canvas =
            PaginatedEditor(
                text: text
            )

        canvas.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondRange =
            canvas.pageRanges[1]

        XCTAssertGreaterThan(
            secondRange.length,
            0
        )

        XCTAssertEqual(
            secondRange.location,
            NSMaxRange(
                canvas.pageRanges[0]
            )
        )

        let page =
            canvas.pageView(
                containing:
                    secondRange.location
            )

        XCTAssertTrue(
            page === canvas.pages[1]
        )

        XCTAssertFalse(
            page === canvas.pages[0]
        )
    }

    func testTerminalPageBreakCaretBelongsToEmptyFinalPage()
        throws {
        let text =
            NSAttributedString(
                string:
                    "Content before terminal break.\u{000C}",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let controller =
            EditorController()

        let canvas =
            PaginatedEditor(
                text: text
            )

        controller.attach(
            canvas.firstView
        )

        canvas.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.pages.count,
            2
        )

        XCTAssertEqual(
            canvas.pageRanges.count,
            2
        )

        XCTAssertEqual(
            canvas.pageRanges[1],
            NSRange(
                location: text.length,
                length: 0
            )
        )

        let finalPage =
            canvas.pageView(
                containing:
                    text.length
            )

        XCTAssertTrue(
            finalPage === canvas.pages[1]
        )

        controller.navigate(
            to:
                NSRange(
                    location:
                        text.length,
                    length: 0
                )
        )

        XCTAssertTrue(
            controller.textView
                === canvas.pages[1]
        )

        XCTAssertEqual(
            controller.selection,
            NSRange(
                location:
                    text.length,
                length: 0
            )
        )

        XCTAssertEqual(
            canvas.pages[1]
                .selectedRange(),
            NSRange(
                location:
                    text.length,
                length: 0
            )
        )
    }



    func testSwitchingPrintLayoutToContinuousPreservesSecondPageSelection()
        throws {
        let document =
            BOLDWriterDocument()

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Selection must stay attached to the same manuscript characters when Print Layout switches to Continuous view.\n",
                        count: 220
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        host.layoutSubtreeIfNeeded()

        let initialView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                initialView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst()
                    .first {
                        $0.length > 12
                    }
            )

        let selection =
            NSRange(
                location:
                    secondRange.location + 3,
                length: 7
            )

        let secondPage =
            canvas.pageView(
                containing:
                    selection.location
            )

        secondPage.setSelectedRange(
            selection
        )

        controller.attach(
            secondPage
        )

        XCTAssertFalse(
            secondPage
                === canvas.firstView
        )

        host.rootView =
            RichTextEditor(
                document: document,
                controller: controller,
                printLayout: false
            )

        host.layoutSubtreeIfNeeded()

        let continuousView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let continuousCanvas =
            try XCTUnwrap(
                continuousView.superview
                    as? PaginatedEditor
            )

        XCTAssertEqual(
            continuousCanvas.pages.count,
            1
        )

        XCTAssertTrue(
            continuousView
                === continuousCanvas.firstView
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        XCTAssertEqual(
            continuousView.selectedRange(),
            selection
        )

        XCTAssertEqual(
            continuousCanvas.flow.storage.string,
            text.string
        )
    }

    func testSwitchingContinuousBackToPrintLayoutRestoresCorrectPage()
        throws {
        let document =
            BOLDWriterDocument()

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Continuous-to-print mode switching must return the caret and selection to the physical page containing the same manuscript text.\n",
                        count: 240
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: false
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        host.layoutSubtreeIfNeeded()

        let continuousView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        _ = try XCTUnwrap(
            continuousView.superview
                as? PaginatedEditor
        )

        let selection =
            NSRange(
                location:
                    min(
                        5500,
                        text.length - 10
                    ),
                length: 6
            )

        continuousView.setSelectedRange(
            selection
        )

        controller.attach(
            continuousView
        )

        host.rootView =
            RichTextEditor(
                document: document,
                controller: controller,
                printLayout: true
            )

        host.layoutSubtreeIfNeeded()

        let printView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let printCanvas =
            try XCTUnwrap(
                printView.superview
                    as? PaginatedEditor
            )

        printCanvas.finishPagination()

        let expectedPage =
            printCanvas.pageView(
                containing:
                    selection.location
            )

        XCTAssertGreaterThan(
            printCanvas.pages.count,
            1
        )

        XCTAssertTrue(
            controller.textView
                === expectedPage
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        XCTAssertEqual(
            expectedPage.selectedRange(),
            selection
        )

        XCTAssertEqual(
            printCanvas.flow.storage.string,
            text.string
        )
    }

    func testPageSetupReflowPreservesSelectionOnCorrectPhysicalPage()
        throws {
        let document =
            BOLDWriterDocument()

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Changing margins or paper geometry must reflow pages without losing the current manuscript selection.\n",
                        count: 260
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        host.layoutSubtreeIfNeeded()

        let initialView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                initialView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            2
        )

        let targetRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst(2)
                    .first {
                        $0.length > 12
                    }
            )

        let selection =
            NSRange(
                location:
                    targetRange.location + 4,
                length: 8
            )

        let activePage =
            canvas.pageView(
                containing:
                    selection.location
            )

        activePage.setSelectedRange(
            selection
        )

        controller.attach(
            activePage
        )

        document.metadata.page.leftMargin =
            108

        document.metadata.page.rightMargin =
            108

        host.rootView =
            RichTextEditor(
                document: document,
                controller: controller,
                printLayout: true
            )

        host.layoutSubtreeIfNeeded()

        let reflowView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let reflowCanvas =
            try XCTUnwrap(
                reflowView.superview
                    as? PaginatedEditor
            )

        reflowCanvas.finishPagination()

        let expectedPage =
            reflowCanvas.pageView(
                containing:
                    selection.location
            )

        XCTAssertTrue(
            controller.textView
                === expectedPage
        )

        XCTAssertEqual(
            controller.selection,
            selection
        )

        XCTAssertEqual(
            expectedPage.selectedRange(),
            selection
        )

        XCTAssertEqual(
            reflowCanvas.flow.storage.string,
            text.string
        )
    }



    func testActiveEditorRehomesWhenRepaginationRemovesItsPage()
        throws {
        let document =
            BOLDWriterDocument()

        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Late-page editing must remain valid when a large deletion causes downstream physical pages to disappear during repagination.\n",
                        count: 420
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: text
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        let window =
            NSWindow(
                contentRect:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 1000,
                        height: 800
                    ),
                styleMask:
                    [.titled],
                backing:
                    .buffered,
                defer: false
            )

        window.contentView =
            host

        window.makeKeyAndOrderFront(
            nil
        )

        host.layoutSubtreeIfNeeded()

        let firstView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                firstView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            4
        )

        let lateIndex =
            canvas.pages.count - 1

        let latePage =
            canvas.pages[lateIndex]

        let lateRange =
            canvas.pageRanges[lateIndex]

        XCTAssertGreaterThan(
            lateRange.length,
            4
        )

        let originalSelection =
            NSRange(
                location:
                    lateRange.location + 1,
                length: 3
            )

        latePage.setSelectedRange(
            originalSelection
        )

        controller.attach(
            latePage
        )

        window.makeFirstResponder(
            latePage
        )

        XCTAssertTrue(
            window.firstResponder
                === latePage
        )

        XCTAssertTrue(
            controller.textView
                === latePage
        )

        let keepLength =
            min(
                1200,
                canvas.flow.storage.length
            )

        canvas.flow.storage
            .deleteCharacters(
                in:
                    NSRange(
                        location:
                            keepLength,
                        length:
                            canvas.flow.storage.length
                            - keepLength
                    )
            )

        canvas.finishPagination()

        XCTAssertLessThan(
            canvas.pages.count,
            lateIndex + 1
        )

        let active =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        XCTAssertTrue(
            canvas.pages.contains(
                where: {
                    $0 === active
                }
            )
        )

        XCTAssertFalse(
            active === latePage
        )

        XCTAssertLessThanOrEqual(
            controller.selection.location,
            canvas.flow.storage.length
        )

        XCTAssertLessThanOrEqual(
            NSMaxRange(
                controller.selection
            ),
            canvas.flow.storage.length
        )

        XCTAssertEqual(
            active.selectedRange(),
            controller.selection
        )

        XCTAssertTrue(
            window.firstResponder
                === active
        )

        window.orderOut(
            nil
        )
    }



    func testMidDocumentPageBreakMatchesPDFPagination()
        throws {
        let before =
            Array(
                repeating:
                    "Content before the explicit manual page break must remain on the earlier physical page.\n",
                count: 16
            )
            .joined()

        let after =
            Array(
                repeating:
                    "Content after the explicit manual page break must begin on the following physical page.\n",
                count: 42
            )
            .joined()

        let string =
            before
            + "\u{000C}"
            + after

        let text =
            NSAttributedString(
                string: string,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let settings =
            PageSettings()

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        let breakLocation =
            (before as NSString).length

        XCTAssertGreaterThanOrEqual(
            editor.pages.count,
            2
        )

        XCTAssertGreaterThanOrEqual(
            editor.pageRanges.count,
            2
        )

        let pageBeforeBreakIndex =
            try XCTUnwrap(
                editor.pageRanges
                    .indices
                    .last {
                        editor.pageRanges[$0]
                            .location
                            <= breakLocation
                    }
            )

        let pageAfterBreakIndex =
            try XCTUnwrap(
                editor.pageRanges
                    .indices
                    .first {
                        editor.pageRanges[$0]
                            .location
                            > breakLocation
                    }
            )

        XCTAssertEqual(
            pageAfterBreakIndex,
            pageBeforeBreakIndex + 1
        )

        XCTAssertEqual(
            editor.pageRanges[
                pageAfterBreakIndex
            ].location,
            breakLocation + 1
        )

        for index
            in 1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index]
                    .location,
                NSMaxRange(
                    editor.pageRanges[
                        index - 1
                    ]
                )
            )
        }

        XCTAssertEqual(
            NSMaxRange(
                try XCTUnwrap(
                    editor.pageRanges.last
                )
            ),
            text.length
        )

        let pdfData =
            try PDFExporter.data(
                from: text,
                settings: settings
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data: pdfData
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            pdf.pageCount
        )

        let firstCharacterAfterBreak =
            breakLocation + 1

        let destinationPage =
            editor.pageView(
                containing:
                    firstCharacterAfterBreak
            )

        XCTAssertTrue(
            destinationPage
                === editor.pages[
                    pageAfterBreakIndex
                ]
        )
    }

    func testLandscapeAndMarginChangesMaintainScreenPDFPaginationParity()
        throws {
        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Page setup changes must use the same typographic geometry on screen and in exported PDF output.\n",
                        count: 360
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var settings =
            PageSettings()

        settings.landscape = true
        settings.topMargin = 54
        settings.bottomMargin = 90
        settings.leftMargin = 108
        settings.rightMargin = 72

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1.35,
            viewportWidth: 1280
        )

        editor.finishPagination()

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertFalse(
            editor.pageRanges.isEmpty
        )

        XCTAssertEqual(
            editor.pageRanges.first?
                .location,
            0
        )

        for index
            in 1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index]
                    .location,
                NSMaxRange(
                    editor.pageRanges[
                        index - 1
                    ]
                )
            )
        }

        XCTAssertEqual(
            NSMaxRange(
                try XCTUnwrap(
                    editor.pageRanges.last
                )
            ),
            text.length
        )

        let pdfData =
            try PDFExporter.data(
                from: text,
                settings: settings
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data: pdfData
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            pdf.pageCount
        )

        let initialPageCount =
            editor.pages.count

        settings.landscape = false
        settings.topMargin = 108
        settings.bottomMargin = 108
        settings.leftMargin = 126
        settings.rightMargin = 126

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 0.8,
            viewportWidth: 720
        )

        editor.finishPagination()

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pageRanges.first?
                .location,
            0
        )

        for index
            in 1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index]
                    .location,
                NSMaxRange(
                    editor.pageRanges[
                        index - 1
                    ]
                )
            )
        }

        XCTAssertEqual(
            NSMaxRange(
                try XCTUnwrap(
                    editor.pageRanges.last
                )
            ),
            text.length
        )

        let portraitPDFData =
            try PDFExporter.data(
                from: text,
                settings: settings
            )

        let portraitPDF =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        portraitPDFData
                )
            )

        XCTAssertEqual(
            editor.pages.count,
            portraitPDF.pageCount
        )

        XCTAssertNotEqual(
            initialPageCount,
            0
        )
    }



    func testOversizedAttachmentFallsBackWithoutChangingDocument()
        throws {
        let attachment =
            NSTextAttachment()

        attachment.bounds =
            NSRect(
                x: 0,
                y: 0,
                width: 1200,
                height: 1200
            )

        let original =
            NSMutableAttributedString(
                string:
                    "Text before oversized image.\n",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        original.append(
            NSAttributedString(
                attachment:
                    attachment
            )
        )

        original.append(
            NSAttributedString(
                string:
                    "\nText after oversized image.",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )
        )

        let snapshot =
            original.copy()
                as! NSAttributedString

        let editor =
            PaginatedEditor(
                text: original
            )

        var reportedFailure:
            String?

        editor.onLayoutFailure = {
            message in

            reportedFailure =
                message
        }

        editor.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertFalse(
            editor.printLayout
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertNotNil(
            editor.lastLayoutError
        )

        XCTAssertNotNil(
            reportedFailure
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        XCTAssertEqual(
            editor.flow.storage.string,
            snapshot.string
        )

        let attachmentLocation =
            (
                snapshot.string
                    as NSString
            )
            .range(
                of:
                    "\u{fffc}"
            )
            .location

        XCTAssertNotEqual(
            attachmentLocation,
            NSNotFound
        )

        let restoredAttachment =
            try XCTUnwrap(
                editor.flow.storage
                    .attribute(
                        .attachment,
                        at:
                            attachmentLocation,
                        effectiveRange: nil
                    )
                    as? NSTextAttachment
            )

        XCTAssertEqual(
            restoredAttachment.bounds.size.width,
            attachment.bounds.size.width,
            accuracy: 0.01
        )

        XCTAssertEqual(
            restoredAttachment.bounds.size.height,
            attachment.bounds.size.height,
            accuracy: 0.01
        )

        let beforeRange =
            (
                snapshot.string
                    as NSString
            )
            .range(
                of:
                    "Text before oversized image."
            )

        let afterRange =
            (
                snapshot.string
                    as NSString
            )
            .range(
                of:
                    "Text after oversized image."
            )

        XCTAssertNotEqual(
            beforeRange.location,
            NSNotFound
        )

        XCTAssertNotEqual(
            afterRange.location,
            NSNotFound
        )

        XCTAssertEqual(
            (
                editor.flow.storage.string
                    as NSString
            )
            .substring(
                with:
                    beforeRange
            ),
            (
                snapshot.string
                    as NSString
            )
            .substring(
                with:
                    beforeRange
            )
        )

        XCTAssertEqual(
            (
                editor.flow.storage.string
                    as NSString
            )
            .substring(
                with:
                    afterRange
            ),
            (
                snapshot.string
                    as NSString
            )
            .substring(
                with:
                    afterRange
            )
        )
    }

    func testLargeManuscriptPaginationRemainsBatchBounded()
        throws {
        let text =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Large manuscript pagination should advance through finite batches without blocking the entire document in one layout slice.\n",
                        count: 4200
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertLessThanOrEqual(
            editor.lastBatchPageCount,
            2
        )

        XCTAssertFalse(
            editor.layoutComplete
        )

        let pagesBefore =
            editor.pageRanges.count

        editor.paginateBatch(
            maxPages: 3
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertLessThanOrEqual(
            editor.lastBatchPageCount,
            3
        )

        XCTAssertGreaterThan(
            editor.pageRanges.count,
            pagesBefore
        )

        XCTAssertFalse(
            editor.layoutComplete
        )

        for index
            in 1..<editor.pageRanges.count {

            XCTAssertEqual(
                editor.pageRanges[index]
                    .location,
                NSMaxRange(
                    editor.pageRanges[
                        index - 1
                    ]
                )
            )
        }

        editor.finishPagination()

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pageRanges.first?
                .location,
            0
        )

        XCTAssertEqual(
            NSMaxRange(
                try XCTUnwrap(
                    editor.pageRanges.last
                )
            ),
            text.length
        )

        XCTAssertGreaterThan(
            editor.pages.count,
            10
        )
    }



    func testRemovingMidDocumentPageBreakMergesAndReflowsPages()
        throws {
        let before =
            Array(
                repeating:
                    "Short content before the removable manual page break.\n",
                count: 8
            )
            .joined()

        let after =
            Array(
                repeating:
                    "Short content after the removable manual page break.\n",
                count: 8
            )
            .joined()

        let breakLocation =
            (before as NSString)
                .length

        let text =
            NSAttributedString(
                string:
                    before
                    + "\u{000C}"
                    + after,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings:
                PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            breakLocation + 1
        )

        editor.flow.storage
            .deleteCharacters(
                in:
                    NSRange(
                        location:
                            breakLocation,
                        length: 1
                    )
            )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.flow.storage
                .string,
            before + after
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges[0],
            NSRange(
                location: 0,
                length:
                    editor.flow.storage
                        .length
            )
        )

        XCTAssertTrue(
            editor.pageView(
                containing:
                    min(
                        breakLocation,
                        editor.flow.storage
                            .length
                    )
            )
                === editor.firstView
        )
    }

    func testCaretRoutingImmediatelyBeforeAndAfterManualPageBreak()
        throws {
        let before =
            Array(
                repeating:
                    "Before explicit break boundary.\n",
                count: 4
            )
            .joined()

        let after =
            Array(
                repeating:
                    "After explicit break boundary.\n",
                count: 4
            )
            .joined()

        let breakLocation =
            (before as NSString)
                .length

        let text =
            NSAttributedString(
                string:
                    before
                    + "\u{000C}"
                    + after,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings:
                PageSettings(),
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            2
        )

        XCTAssertEqual(
            NSMaxRange(
                editor.pageRanges[0]
            ),
            breakLocation + 1
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            breakLocation + 1
        )

        let beforeBreakPage =
            editor.pageView(
                containing:
                    breakLocation
            )

        let afterBreakPage =
            editor.pageView(
                containing:
                    breakLocation + 1
            )

        XCTAssertTrue(
            beforeBreakPage
                === editor.pages[0]
        )

        XCTAssertTrue(
            afterBreakPage
                === editor.pages[1]
        )

        XCTAssertFalse(
            beforeBreakPage
                === afterBreakPage
        )

        let controller =
            EditorController()

        controller.attach(
            editor.firstView
        )

        controller.navigate(
            to:
                NSRange(
                    location:
                        breakLocation,
                    length: 0
                )
        )

        XCTAssertTrue(
            controller.textView
                === editor.pages[0]
        )

        XCTAssertEqual(
            controller.selection,
            NSRange(
                location:
                    breakLocation,
                length: 0
            )
        )

        controller.navigate(
            to:
                NSRange(
                    location:
                        breakLocation + 1,
                    length: 0
                )
        )

        XCTAssertTrue(
            controller.textView
                === editor.pages[1]
        )

        XCTAssertEqual(
            controller.selection,
            NSRange(
                location:
                    breakLocation + 1,
                length: 0
            )
        )
    }



    func testTerminalBlankPageReceivesSecondPhysicalPageNumber()
        throws {
        var settings =
            PageSettings()

        settings.headerText =
            "Screen Header"

        settings.footerText =
            "Screen Footer"

        settings.showsPageNumbers =
            true

        settings.suppressFirstPageHeaderFooter =
            true

        let text =
            NSAttributedString(
                string:
                    "Visible first page\u{000C}",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text: text
            )

        editor.configure(
            printLayout: true,
            settings: settings,
            zoom: 1,
            viewportWidth: 900
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            2
        )

        XCTAssertEqual(
            editor.pages[0]
                .pageNumber,
            1
        )

        XCTAssertEqual(
            editor.pages[1]
                .pageNumber,
            2
        )

        XCTAssertTrue(
            editor.pages[0]
                .pageGeometry?
                .settings
                .hidesHeaderFooterOnFirstPage
                == true
        )

        XCTAssertTrue(
            editor.pages[1]
                .pageGeometry?
                .settings
                .hidesHeaderFooterOnFirstPage
                == true
        )

        XCTAssertEqual(
            editor.pages[1]
                .pageGeometry?
                .settings
                .effectiveHeaderText,
            "Screen Header"
        )

        XCTAssertEqual(
            editor.pages[1]
                .pageGeometry?
                .settings
                .footerText,
            "Screen Footer"
        )

        XCTAssertEqual(
            editor.pageRanges[1],
            NSRange(
                location:
                    text.length,
                length: 0
            )
        )
    }



    func testSecondPageUndoRedoKeepsControllerOnCorrectPhysicalPage()
        throws {
        let document =
            BOLDWriterDocument()

        let original =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "Undo and redo must remain connected to the physical page where the writer is actively editing.\n",
                        count: 180
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: original
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        let window =
            NSWindow(
                contentRect:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 1000,
                        height: 800
                    ),
                styleMask:
                    [.titled],
                backing:
                    .buffered,
                defer: false
            )

        window.contentView =
            host

        window.makeKeyAndOrderFront(
            nil
        )

        host.layoutSubtreeIfNeeded()

        let firstView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                firstView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let secondRange =
            try XCTUnwrap(
                canvas.pageRanges
                    .dropFirst()
                    .first {
                        $0.length > 12
                    }
            )

        let insertionPoint =
            secondRange.location + 4

        let secondPage =
            canvas.pageView(
                containing:
                    insertionPoint
            )

        let originalSelection =
            NSRange(
                location:
                    insertionPoint,
                length: 0
            )

        secondPage.setSelectedRange(
            originalSelection
        )

        controller.attach(
            secondPage
        )

        window.makeFirstResponder(
            secondPage
        )

        let originalString =
            canvas.flow.storage
                .string

        controller.replace(
            range:
                originalSelection,
            with:
                NSAttributedString(
                    string:
                        "UNDO",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                ),
            actionName:
                "Second Page Edit"
        )

        canvas.finishPagination()

        XCTAssertTrue(
            canvas.sharedUndoManager
                .canUndo
        )

        let editedPage =
            canvas.pageView(
                containing:
                    insertionPoint
            )

        XCTAssertTrue(
            controller.textView
                === editedPage
        )

        XCTAssertTrue(
            window.firstResponder
                === editedPage
        )

        canvas.sharedUndoManager
            .undo()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .string,
            originalString
        )

        let undoPage =
            canvas.pageView(
                containing:
                    originalSelection.location
            )

        XCTAssertTrue(
            controller.textView
                === undoPage
        )

        XCTAssertEqual(
            controller.selection,
            originalSelection
        )

        XCTAssertTrue(
            window.firstResponder
                === undoPage
        )

        XCTAssertTrue(
            canvas.sharedUndoManager
                .canRedo
        )

        canvas.sharedUndoManager
            .redo()

        canvas.finishPagination()

        XCTAssertEqual(
            (
                canvas.flow.storage
                    .string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            insertionPoint,
                        length: 4
                    )
            ),
            "UNDO"
        )

        let redoPage =
            canvas.pageView(
                containing:
                    controller.selection
                        .location
            )

        XCTAssertTrue(
            controller.textView
                === redoPage
        )

        XCTAssertTrue(
            window.firstResponder
                === redoPage
        )

        window.orderOut(
            nil
        )
    }

    func testUndoRecreatesRemovedPagesAndRoutesControllerBackToLatePage()
        throws {
        let document =
            BOLDWriterDocument()

        let original =
            NSAttributedString(
                string:
                    Array(
                        repeating:
                            "A long manuscript edit can remove many physical pages, and Undo must recreate those pages without leaving the controller attached to the wrong editor.\n",
                        count: 430
                    )
                    .joined(),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: original
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        let window =
            NSWindow(
                contentRect:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 1000,
                        height: 800
                    ),
                styleMask:
                    [.titled],
                backing:
                    .buffered,
                defer: false
            )

        window.contentView =
            host

        window.makeKeyAndOrderFront(
            nil
        )

        host.layoutSubtreeIfNeeded()

        let firstView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                firstView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        let originalPageCount =
            canvas.pages.count

        XCTAssertGreaterThan(
            originalPageCount,
            4
        )

        let lateIndex =
            originalPageCount - 1

        let lateRange =
            canvas.pageRanges[
                lateIndex
            ]

        XCTAssertGreaterThan(
            lateRange.length,
            8
        )

        let originalSelection =
            NSRange(
                location:
                    lateRange.location + 2,
                length: 3
            )

        let latePage =
            canvas.pages[
                lateIndex
            ]

        latePage.setSelectedRange(
            originalSelection
        )

        controller.attach(
            latePage
        )

        window.makeFirstResponder(
            latePage
        )

        XCTAssertTrue(
            window.firstResponder
                === latePage
        )

        let originalLength =
            canvas.flow.storage
                .length

        let keepLength =
            min(
                1200,
                max(
                    1,
                    lateRange.location / 2
                )
            )

        XCTAssertLessThan(
            keepLength,
            originalSelection.location
        )

        controller.replace(
            range:
                NSRange(
                    location:
                        keepLength,
                    length:
                        canvas.flow.storage
                            .length
                        - keepLength
                ),
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Large Multi Page Delete"
        )

        canvas.finishPagination()

        let shrunkenPageCount =
            canvas.pages.count

        XCTAssertLessThan(
            shrunkenPageCount,
            originalPageCount
        )

        let survivingView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        XCTAssertTrue(
            canvas.pages.contains(
                where: {
                    $0 === survivingView
                }
            )
        )

        XCTAssertFalse(
            survivingView
                === latePage
        )

        XCTAssertTrue(
            window.firstResponder
                === survivingView
        )

        XCTAssertTrue(
            canvas.sharedUndoManager
                .canUndo
        )

        canvas.sharedUndoManager
            .undo()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .length,
            originalLength
        )

        XCTAssertEqual(
            canvas.pages.count,
            originalPageCount
        )

        let restoredLatePage =
            canvas.pageView(
                containing:
                    originalSelection.location
            )

        XCTAssertTrue(
            controller.textView
                === restoredLatePage
        )

        XCTAssertEqual(
            controller.selection,
            originalSelection
        )

        XCTAssertEqual(
            restoredLatePage
                .selectedRange(),
            originalSelection
        )

        XCTAssertTrue(
            window.firstResponder
                === restoredLatePage
        )

        XCTAssertTrue(
            canvas.sharedUndoManager
                .canRedo
        )

        canvas.sharedUndoManager
            .redo()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .length,
            keepLength
        )

        XCTAssertEqual(
            canvas.pages.count,
            shrunkenPageCount
        )

        let redoView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        XCTAssertTrue(
            canvas.pages.contains(
                where: {
                    $0 === redoView
                }
            )
        )

        let redoDestination =
            canvas.pageView(
                containing:
                    controller.selection
                        .location
            )

        XCTAssertTrue(
            redoView
                === redoDestination
        )

        XCTAssertTrue(
            window.firstResponder
                === redoDestination
        )

        window.orderOut(
            nil
        )
    }

    func testUndoRedoManualPageBreakDeletionPreservesBoundaryRouting()
        throws {
        let document =
            BOLDWriterDocument()

        let original =
            NSAttributedString(
                string:
                    "Before\u{000C}After",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        document.replaceText(
            with: original
        )

        let controller =
            EditorController()

        let host =
            NSHostingView(
                rootView:
                    RichTextEditor(
                        document: document,
                        controller: controller,
                        printLayout: true
                    )
            )

        host.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 1000,
                height: 800
            )

        let window =
            NSWindow(
                contentRect:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 1000,
                        height: 800
                    ),
                styleMask:
                    [.titled],
                backing:
                    .buffered,
                defer: false
            )

        window.contentView =
            host

        window.makeKeyAndOrderFront(
            nil
        )

        host.layoutSubtreeIfNeeded()

        let firstView =
            try XCTUnwrap(
                controller.textView
                    as? WritingTextView
            )

        let canvas =
            try XCTUnwrap(
                firstView.superview
                    as? PaginatedEditor
            )

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.pages.count,
            2
        )

        let breakLocation =
            6

        let afterBreakLocation =
            breakLocation + 1

        let secondPage =
            canvas.pageView(
                containing:
                    afterBreakLocation
            )

        XCTAssertFalse(
            secondPage
                === canvas.firstView
        )

        let afterBreakSelection =
            NSRange(
                location:
                    afterBreakLocation,
                length: 0
            )

        secondPage.setSelectedRange(
            afterBreakSelection
        )

        controller.attach(
            secondPage
        )

        window.makeFirstResponder(
            secondPage
        )

        controller.replace(
            range:
                NSRange(
                    location:
                        breakLocation,
                    length: 1
                ),
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Remove Page Break"
        )

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .string,
            "BeforeAfter"
        )

        XCTAssertEqual(
            canvas.pages.count,
            1
        )

        XCTAssertTrue(
            controller.textView
                === canvas.firstView
        )

        XCTAssertTrue(
            window.firstResponder
                === canvas.firstView
        )

        canvas.sharedUndoManager
            .undo()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .string,
            "Before\u{000C}After"
        )

        XCTAssertEqual(
            canvas.pages.count,
            2
        )

        let restoredSecondPage =
            canvas.pageView(
                containing:
                    afterBreakLocation
            )

        XCTAssertFalse(
            restoredSecondPage
                === canvas.firstView
        )

        XCTAssertTrue(
            controller.textView
                === restoredSecondPage
        )

        XCTAssertEqual(
            controller.selection,
            afterBreakSelection
        )

        XCTAssertTrue(
            window.firstResponder
                === restoredSecondPage
        )

        canvas.sharedUndoManager
            .redo()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.flow.storage
                .string,
            "BeforeAfter"
        )

        XCTAssertEqual(
            canvas.pages.count,
            1
        )

        XCTAssertTrue(
            controller.textView
                === canvas.firstView
        )

        XCTAssertLessThanOrEqual(
            NSMaxRange(
                controller.selection
            ),
            canvas.flow.storage
                .length
        )

        XCTAssertTrue(
            window.firstResponder
                === canvas.firstView
        )

        window.orderOut(
            nil
        )
    }


}

extension WritingInterfaceTests {
    func testPaginatedEditorResolvesPageSettingsFromDocumentSections()
        throws {

        let string =
            "Alpha🙂\nBeta section"

        let text =
            NSAttributedString(
                string:
                    string
            )

        let ns =
            string as NSString

        let boundary =
            ns.range(
                of:
                    "Beta"
            )
            .location

        var first =
            PageSettings()

        first.footerText =
            "FIRST SECTION"

        first.showsPageNumbers =
            false

        first.leftMargin =
            54

        var second =
            PageSettings()

        second.footerText =
            "SECOND SECTION"

        second.showsPageNumbers =
            true

        second.leftMargin =
            90

        second.landscape =
            true

        let canvas =
            PaginatedEditor(
                text:
                    text
            )

        canvas.configure(
            printLayout:
                false,
            settings:
                first,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            second
                    )
                ],
            zoom:
                1,
            viewportWidth:
                900
        )

        XCTAssertEqual(
            canvas.sections.count,
            2
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    0
            )
            .footerText,
            "FIRST SECTION"
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    boundary - 1
            )
            .footerText,
            "FIRST SECTION"
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    boundary
            )
            .footerText,
            "SECOND SECTION"
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    ns.length
            )
            .footerText,
            "SECOND SECTION"
        )

        XCTAssertFalse(
            canvas.pageSettings(
                forCharacter:
                    0
            )
            .showsPageNumbers
        )

        XCTAssertTrue(
            canvas.pageSettings(
                forCharacter:
                    boundary
            )
            .showsPageNumbers
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    boundary
            )
            .leftMargin,
            90
        )

        let secondGeometry =
            try canvas.pageGeometry(
                forCharacter:
                    boundary
            )

        XCTAssertEqual(
            secondGeometry.settings,
            second
        )

        XCTAssertEqual(
            secondGeometry.contentOrigin.x,
            90
        )

        XCTAssertEqual(
            secondGeometry.size,
            second.pageSize
        )

        XCTAssertGreaterThan(
            boundary,
            string.distance(
                from:
                    string.startIndex,
                to:
                    string.range(
                        of:
                            "Beta"
                    )!
                    .lowerBound
            )
        )
    }

    func testPaginatedEditorUsesFallbackPageWithoutSections() {
        var fallback =
            PageSettings()

        fallback.footerText =
            "GLOBAL"

        fallback.showsPageNumbers =
            false

        let canvas =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "One section"
                    )
            )

        canvas.configure(
            printLayout:
                false,
            settings:
                fallback,
            sections:
                nil,
            zoom:
                1,
            viewportWidth:
                900
        )

        XCTAssertEqual(
            canvas.sections.count,
            1
        )

        XCTAssertEqual(
            canvas.sections[0].location,
            0
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    0
            ),
            fallback
        )

        XCTAssertEqual(
            canvas.pageSettings(
                forCharacter:
                    999
            ),
            fallback
        )
    }
}

extension WritingInterfaceTests {
    func testPaginatedEditorUsesSectionGeometryOnEachPhysicalPage()
        throws {

        let firstText =
            "Portrait section"

        let secondText =
            "Landscape section"

        let complete =
            firstText
            + "\u{000C}"
            + secondText

        let boundary =
            (
                firstText
                + "\u{000C}"
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    complete,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var first =
            PageSettings()

        first.paper =
            .letter

        first.landscape =
            false

        first.topMargin =
            72

        first.bottomMargin =
            72

        first.leftMargin =
            54

        first.rightMargin =
            54

        first.footerText =
            "PORTRAIT"

        var second =
            PageSettings()

        second.paper =
            .letter

        second.landscape =
            true

        second.topMargin =
            36

        second.bottomMargin =
            54

        second.leftMargin =
            90

        second.rightMargin =
            72

        second.footerText =
            "LANDSCAPE"

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            second
                    )
                ],
            zoom:
                1,
            viewportWidth:
                1200
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            boundary
        )

        let firstGeometry =
            try XCTUnwrap(
                editor.pages[0]
                    .pageGeometry
            )

        let secondGeometry =
            try XCTUnwrap(
                editor.pages[1]
                    .pageGeometry
            )

        XCTAssertEqual(
            firstGeometry.settings,
            first
        )

        XCTAssertEqual(
            secondGeometry.settings,
            second
        )

        XCTAssertEqual(
            firstGeometry.size,
            first.pageSize
        )

        XCTAssertEqual(
            secondGeometry.size,
            second.pageSize
        )

        XCTAssertEqual(
            editor.pages[0]
                .textContainer?
                .containerSize,
            firstGeometry.contentSize
        )

        XCTAssertEqual(
            editor.pages[1]
                .textContainer?
                .containerSize,
            secondGeometry.contentSize
        )

        XCTAssertEqual(
            editor.pages[0]
                .frame.size,
            first.pageSize
        )

        XCTAssertEqual(
            editor.pages[1]
                .frame.size,
            second.pageSize
        )

        XCTAssertEqual(
            editor.pages[0]
                .frame.origin.y,
            24,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            editor.pages[1]
                .frame.origin.y,
            24
                + first.pageSize.height
                + 24,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            editor.pages[0]
                .frame.midX,
            editor.pages[1]
                .frame.midX,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            editor.pages[0]
                .writingMargins.left,
            first.leftMargin,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            editor.pages[1]
                .writingMargins.left,
            second.leftMargin,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            editor.pages[0]
                .pageNumber,
            1
        )

        XCTAssertEqual(
            editor.pages[1]
                .pageNumber,
            2
        )
    }
}

extension WritingInterfaceTests {
    func testNativeSectionBoundaryStartsNewPhysicalPage()
        throws {

        let firstText =
            "First section is intentionally short.\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        var first =
            PageSettings()

        first.footerText =
            "FIRST"

        var second =
            PageSettings()

        second.footerText =
            "SECOND"

        second.landscape =
            true

        let editor =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            firstText
                            + "Second section is also short.",
                        attributes: [
                            .font:
                                NSFont.systemFont(
                                    ofSize: 15
                                )
                        ]
                    )
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            second
                    )
                ],
            zoom:
                1,
            viewportWidth:
                1200
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            NSMaxRange(
                editor.pageRanges[0]
            ),
            boundary
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            boundary
        )

        XCTAssertEqual(
            editor.pages[0]
                .sectionPageNumber,
            1
        )

        XCTAssertEqual(
            editor.pages[1]
                .sectionPageNumber,
            1
        )

        XCTAssertEqual(
            editor.pages.map(
                \.pageNumber
            ),
            [
                1,
                2
            ]
        )
    }

    func testSectionPageNumberResetsWhilePhysicalNumbersContinue()
        throws {

        let firstPage =
            "First section page one\u{000C}"

        let secondPage =
            "First section page two\n"

        let boundary =
            (
                firstPage
                + secondPage
                as NSString
            )
            .length

        var first =
            PageSettings()

        first.headerText =
            "FIRST SECTION"

        var second =
            PageSettings()

        second.headerText =
            "SECOND SECTION"

        let editor =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            firstPage
                            + secondPage
                            + "Second section page one",
                        attributes: [
                            .font:
                                NSFont.systemFont(
                                    ofSize: 15
                                )
                        ]
                    )
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            second
                    )
                ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            3
        )

        XCTAssertEqual(
            editor.pages.map(
                \.pageNumber
            ),
            [
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            editor.pages.map(
                \.sectionPageNumber
            ),
            [
                1,
                2,
                1
            ]
        )

        XCTAssertEqual(
            editor.pageRanges[2]
                .location,
            boundary
        )
    }

    func testPageGeometrySelectsFirstOddEvenFurniture()
        throws {

        var settings =
            PageSettings()

        settings.headerText =
            "ODD HEADER"

        settings.footerText =
            "ODD FOOTER"

        settings.differentOddEvenHeaderFooter =
            true

        settings.evenPageHeaderText =
            "EVEN HEADER"

        settings.evenPageFooterText =
            "EVEN FOOTER"

        settings.firstPageHeaderText =
            "FIRST HEADER"

        settings.firstPageFooterText =
            "FIRST FOOTER"

        settings.suppressFirstPageHeaderFooter =
            false

        let geometry =
            try PageGeometry(
                settings
            )

        let first =
            geometry.furniture(
                page: 2,
                sectionPage: 1
            )

        XCTAssertFalse(
            first.hidden
        )

        XCTAssertEqual(
            first.headerText,
            "FIRST HEADER"
        )

        XCTAssertEqual(
            first.footerText,
            "FIRST FOOTER"
        )

        let even =
            geometry.furniture(
                page: 2,
                sectionPage: 2
            )

        XCTAssertEqual(
            even.headerText,
            "EVEN HEADER"
        )

        XCTAssertEqual(
            even.footerText,
            "EVEN FOOTER"
        )

        let odd =
            geometry.furniture(
                page: 3,
                sectionPage: 3
            )

        XCTAssertEqual(
            odd.headerText,
            "ODD HEADER"
        )

        XCTAssertEqual(
            odd.footerText,
            "ODD FOOTER"
        )

        // Legacy callers that do not supply a section-local page
        // must retain physical-page first-page semantics.
        let legacySecondPage =
            geometry.furniture(
                page: 2
            )

        XCTAssertEqual(
            legacySecondPage.headerText,
            "EVEN HEADER"
        )

        XCTAssertEqual(
            legacySecondPage.footerText,
            "EVEN FOOTER"
        )

        var suppressed =
            settings

        suppressed.firstPageHeaderText =
            nil

        suppressed.firstPageFooterText =
            nil

        suppressed.suppressFirstPageHeaderFooter =
            true

        let suppressedGeometry =
            try PageGeometry(
                suppressed
            )

        XCTAssertTrue(
            suppressedGeometry
                .furniture(
                    page: 1
                )
                .hidden
        )

        XCTAssertFalse(
            suppressedGeometry
                .furniture(
                    page: 2
                )
                .hidden
        )

        XCTAssertTrue(
            suppressedGeometry
                .furniture(
                    page: 2,
                    sectionPage: 1
                )
                .hidden
        )
    }
}

extension WritingInterfaceTests {
    func testSectionAwarePDFMatchesScreenGeometryAndFurniture()
        throws {

        let firstText =
            "FIRST BODY\n"

        let secondText =
            "SECOND BODY"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + secondText,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var first =
            PageSettings()

        first.headerText =
            "FIRST ODD HEADER"

        first.footerText =
            "FIRST ODD FOOTER"

        first.firstPageHeaderText =
            "FIRST SECTION FIRST HEADER"

        first.firstPageFooterText =
            "FIRST SECTION FIRST FOOTER"

        first.suppressFirstPageHeaderFooter =
            false

        first.showsPageNumbers =
            true

        var second =
            PageSettings()

        second.landscape =
            true

        second.headerText =
            "SECOND ODD HEADER"

        second.footerText =
            "SECOND ODD FOOTER"

        second.differentOddEvenHeaderFooter =
            true

        second.evenPageHeaderText =
            "SECOND EVEN HEADER"

        second.evenPageFooterText =
            "SECOND EVEN FOOTER"

        second.firstPageHeaderText =
            "SECOND SECTION FIRST HEADER"

        second.firstPageFooterText =
            "SECOND SECTION FIRST FOOTER"

        second.suppressFirstPageHeaderFooter =
            false

        second.showsPageNumbers =
            true

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    second
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1200
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        let pdfData =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    first,
                sections:
                    sections
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        pdfData
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        let firstPDFPage =
            try XCTUnwrap(
                pdf.page(
                    at:
                        0
                )
            )

        let secondPDFPage =
            try XCTUnwrap(
                pdf.page(
                    at:
                        1
                )
            )

        let firstScreenSize =
            try XCTUnwrap(
                editor.pages[0]
                    .pageGeometry?
                    .size
            )

        let secondScreenSize =
            try XCTUnwrap(
                editor.pages[1]
                    .pageGeometry?
                    .size
            )

        let firstPDFSize =
            firstPDFPage.bounds(
                for:
                    .mediaBox
            )
            .size

        let secondPDFSize =
            secondPDFPage.bounds(
                for:
                    .mediaBox
            )
            .size

        XCTAssertEqual(
            firstPDFSize.width,
            firstScreenSize.width,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            firstPDFSize.height,
            firstScreenSize.height,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            secondPDFSize.width,
            secondScreenSize.width,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            secondPDFSize.height,
            secondScreenSize.height,
            accuracy:
                0.01
        )

        XCTAssertNotEqual(
            firstPDFSize,
            secondPDFSize
        )

        let firstString =
            try XCTUnwrap(
                firstPDFPage.string
            )

        let secondString =
            try XCTUnwrap(
                secondPDFPage.string
            )

        XCTAssertTrue(
            firstString.contains(
                "FIRST BODY"
            )
        )

        XCTAssertTrue(
            firstString.contains(
                "FIRST SECTION FIRST HEADER"
            )
        )

        XCTAssertTrue(
            firstString.contains(
                "FIRST SECTION FIRST FOOTER"
            )
        )

        XCTAssertFalse(
            firstString.contains(
                "FIRST ODD HEADER"
            )
        )

        XCTAssertTrue(
            secondString.contains(
                "SECOND BODY"
            )
        )

        // Physical page 2 is even, but it is also page 1 of
        // section 2. First-page furniture must win.
        XCTAssertTrue(
            secondString.contains(
                "SECOND SECTION FIRST HEADER"
            )
        )

        XCTAssertTrue(
            secondString.contains(
                "SECOND SECTION FIRST FOOTER"
            )
        )

        XCTAssertFalse(
            secondString.contains(
                "SECOND EVEN HEADER"
            )
        )

        XCTAssertFalse(
            secondString.contains(
                "SECOND EVEN FOOTER"
            )
        )

        XCTAssertTrue(
            secondString.contains(
                "2"
            )
        )

        XCTAssertEqual(
            editor.pages.map(
                \.sectionPageNumber
            ),
            [
                1,
                1
            ]
        )
    }

    func testExportServicePassesDocumentSectionsToPDF()
        throws {

        let firstText =
            "PORTRAIT BODY\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        firstText
                        + "LANDSCAPE BODY",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )
        )

        var portrait =
            PageSettings()

        portrait.footerText =
            "PORTRAIT FOOTER"

        var landscape =
            PageSettings()

        landscape.landscape =
            true

        landscape.footerText =
            "LANDSCAPE FOOTER"

        document.metadata.page =
            portrait

        document.metadata.sections = [
            DocumentSection(
                location:
                    0,
                page:
                    portrait
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    landscape
            )
        ]

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        ExportService.data(
                            for:
                                .pdf,
                            document:
                                document
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            2
        )

        let first =
            try XCTUnwrap(
                pdf.page(
                    at:
                        0
                )
            )

        let second =
            try XCTUnwrap(
                pdf.page(
                    at:
                        1
                )
            )

        XCTAssertLessThan(
            first.bounds(
                for:
                    .mediaBox
            )
            .width,
            first.bounds(
                for:
                    .mediaBox
            )
            .height
        )

        XCTAssertGreaterThan(
            second.bounds(
                for:
                    .mediaBox
            )
            .width,
            second.bounds(
                for:
                    .mediaBox
            )
            .height
        )

        XCTAssertTrue(
            first.string?
                .contains(
                    "PORTRAIT FOOTER"
                )
            == true
        )

        XCTAssertTrue(
            second.string?
                .contains(
                    "LANDSCAPE FOOTER"
                )
            == true
        )
    }
}

extension WritingInterfaceTests {
    func testContinuousSectionStaysOnCurrentPhysicalPageAndPDFMatches()
        throws {

        let firstText =
            "FIRST CONTINUOUS BODY\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + "SECOND CONTINUOUS BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var page =
            PageSettings()

        page.footerText =
            ""

        page.showsPageNumbers =
            false

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    page
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    page,
                breakType:
                    .continuous
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                page,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        XCTAssertEqual(
            editor.pageContainerIndices,
            [
                [
                    0
                ]
            ]
        )

        XCTAssertTrue(
            editor.syntheticBlankPages
                .isEmpty
        )

        XCTAssertFalse(
            editor.flow
                .sectionBreakLocations
                .contains(
                    boundary
                )
        )

        XCTAssertEqual(
            editor.pageRanges.count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges[0],
            NSRange(
                location:
                    0,
                length:
                    text.length
            )
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                page,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            1
        )

        let pageText =
            try XCTUnwrap(
                pdf.page(
                    at:
                        0
                )?
                .string
            )

        XCTAssertTrue(
            pageText.contains(
                "FIRST CONTINUOUS BODY"
            )
        )

        XCTAssertTrue(
            pageText.contains(
                "SECOND CONTINUOUS BODY"
            )
        )
    }

    func testOddPageSectionUsesPhysicalBlankOutsideTextKit()
        throws {

        let firstText =
            "FIRST SECTION BODY\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + "ODD SECTION BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var first =
            PageSettings()

        first.footerText =
            "FIRST FOOTER"

        var second =
            PageSettings()

        second.footerText =
            "ODD FOOTER"

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    second,
                breakType:
                    .oddPage
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            3
        )

        XCTAssertEqual(
            editor.syntheticBlankPages,
            Set(
                [
                    1
                ]
            )
        )

        XCTAssertEqual(
            editor.pageContainerIndices.count,
            3
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0],
            [
                0
            ]
        )

        XCTAssertEqual(
            editor.pageContainerIndices[1],
            []
        )

        XCTAssertEqual(
            editor.pageContainerIndices[2],
            [
                1
            ]
        )

        XCTAssertEqual(
            editor.flow
                .manager
                .textContainers
                .count,
            2
        )

        XCTAssertNil(
            editor.pages[1]
                .textContainer
        )

        XCTAssertEqual(
            NSMaxRange(
                editor.pageRanges[0]
            ),
            boundary
        )

        XCTAssertEqual(
            editor.pageRanges[1],
            NSRange(
                location:
                    boundary,
                length:
                    0
            )
        )

        XCTAssertEqual(
            editor.pageRanges[2],
            NSRange(
                location:
                    boundary,
                length:
                    text.length
                        - boundary
            )
        )

        XCTAssertEqual(
            editor.pages.map(
                \.pageNumber
            ),
            [
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            editor.pages.map(
                \.sectionPageNumber
            ),
            [
                1,
                2,
                1
            ]
        )

        XCTAssertTrue(
            editor.pageView(
                containing:
                    boundary
            )
            === editor.pages[2]
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                first,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            3
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    0
            )?
            .string?
            .contains(
                "FIRST SECTION BODY"
            )
            ?? false
        )

        XCTAssertFalse(
            pdf.page(
                at:
                    1
            )?
            .string?
            .contains(
                "ODD SECTION BODY"
            )
            ?? false
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    2
            )?
            .string?
            .contains(
                "ODD SECTION BODY"
            )
            ?? false
        )
    }

    func testEvenPageSectionUsesImmediateEvenPhysicalPage()
        throws {

        let firstText =
            "FIRST BODY\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + "EVEN SECTION BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var page =
            PageSettings()

        page.footerText =
            ""

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    page
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    page,
                breakType:
                    .evenPage
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                page,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertTrue(
            editor.syntheticBlankPages
                .isEmpty
        )

        XCTAssertEqual(
            editor.flow
                .manager
                .textContainers
                .count,
            2
        )

        XCTAssertEqual(
            editor.pages[1]
                .pageNumber,
            2
        )

        XCTAssertEqual(
            editor.pages[1]
                .sectionPageNumber,
            1
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                page,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            2
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    1
            )?
            .string?
            .contains(
                "EVEN SECTION BODY"
            )
            ?? false
        )
    }

    func testEvenPageSectionAddsPhysicalBlankWhenNextPageIsOdd()
        throws {

        let firstSection =
            "FIRST PHYSICAL PAGE\u{000C}"
            + "SECOND PHYSICAL PAGE\n"

        let boundary =
            (
                firstSection
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstSection
                    + "EVEN SECTION BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var first =
            PageSettings()

        first.footerText =
            "FIRST FOOTER"

        var second =
            PageSettings()

        second.footerText =
            "EVEN FOOTER"

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    second,
                breakType:
                    .evenPage
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            4
        )

        XCTAssertEqual(
            editor.syntheticBlankPages,
            Set(
                [
                    2
                ]
            )
        )

        XCTAssertEqual(
            editor.flow
                .manager
                .textContainers
                .count,
            3
        )

        XCTAssertEqual(
            editor.pageContainerIndices,
            [
                [
                    0
                ],
                [
                    1
                ],
                [],
                [
                    2
                ]
            ]
        )

        XCTAssertEqual(
            editor.pageRanges[2],
            NSRange(
                location:
                    boundary,
                length:
                    0
            )
        )

        XCTAssertEqual(
            editor.pageRanges[3]
                .location,
            boundary
        )

        XCTAssertEqual(
            editor.pages.map(
                \.pageNumber
            ),
            [
                1,
                2,
                3,
                4
            ]
        )

        XCTAssertEqual(
            editor.pages.map(
                \.sectionPageNumber
            ),
            [
                1,
                2,
                3,
                1
            ]
        )

        XCTAssertTrue(
            editor.pageView(
                containing:
                    boundary
            )
            === editor.pages[3]
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                first,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            4
        )

        XCTAssertFalse(
            pdf.page(
                at:
                    2
            )?
            .string?
            .contains(
                "EVEN SECTION BODY"
            )
            ?? false
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    3
            )?
            .string?
            .contains(
                "EVEN SECTION BODY"
            )
            ?? false
        )
    }

    func testParityBlankCanDisappearAfterSectionTypeChanges()
        throws {

        let firstText =
            "FIRST SECTION BODY\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + "SECOND SECTION BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        var page =
            PageSettings()

        page.footerText =
            ""

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                page,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            page
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            page,
                        breakType:
                            .oddPage
                    )
                ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            3
        )

        XCTAssertEqual(
            editor.syntheticBlankPages,
            Set(
                [
                    1
                ]
            )
        )

        editor.configure(
            printLayout:
                true,
            settings:
                page,
            sections:
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            page
                    ),
                    DocumentSection(
                        location:
                            boundary,
                        page:
                            page,
                        breakType:
                            .evenPage
                    )
                ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            2
        )

        XCTAssertTrue(
            editor.syntheticBlankPages
                .isEmpty
        )

        XCTAssertEqual(
            editor.pageContainerIndices,
            [
                [
                    0
                ],
                [
                    1
                ]
            ]
        )

        XCTAssertEqual(
            editor.flow
                .manager
                .textContainers
                .count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            boundary
        )
    }
}


extension WritingInterfaceTests {
    func testSectionPageNumberRestartContinuesAndRestartsOnScreenAndPDF()
        throws {

        let firstText =
            "ALPHA\n"

        let secondText =
            "BETA\n"

        let firstBoundary =
            (
                firstText
                as NSString
            )
            .length

        let secondBoundary =
            (
                firstText
                + secondText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + secondText
                    + "GAMMA",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        var first =
            PageSettings()

        first.footerText =
            ""

        first.showsPageNumbers =
            true

        first.pageNumberStart =
            5

        var second =
            PageSettings()

        second.footerText =
            ""

        second.showsPageNumbers =
            true

        second.pageNumberStart =
            nil

        var third =
            PageSettings()

        third.footerText =
            ""

        third.showsPageNumbers =
            true

        third.pageNumberStart =
            12

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    firstBoundary,
                page:
                    second
            ),
            DocumentSection(
                location:
                    secondBoundary,
                page:
                    third
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            3
        )

        XCTAssertEqual(
            editor.pages.map(
                \.pageNumber
            ),
            [
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            editor.pages.map(
                \.displayPageNumber
            ),
            [
                5,
                6,
                12
            ]
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                first,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            3
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    0
            )?
            .string?
            .contains(
                "5"
            )
            ?? false
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    1
            )?
            .string?
            .contains(
                "6"
            )
            ?? false
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    2
            )?
            .string?
            .contains(
                "12"
            )
            ?? false
        )
    }

    func testPDFUsesLowerRomanSectionPageNumbers()
        throws {

        var page =
            PageSettings()

        page.footerText =
            ""

        page.showsPageNumbers =
            true

        page.pageNumberStart =
            4

        page.pageNumberFormat =
            "lowerRoman"

        let text =
            NSAttributedString(
                string:
                    "ROMAN BODY",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    page
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        XCTAssertTrue(
            pdf.page(
                at:
                    0
            )?
            .string?
            .contains(
                "iv"
            )
            ?? false
        )
    }

    func testPageGeometryCalculatesEqualSectionColumns() throws {
        var settings = PageSettings()
        settings.paper = .letter
        settings.landscape = false
        settings.leftMargin = 72
        settings.rightMargin = 72
        settings.topMargin = 72
        settings.bottomMargin = 72
        settings.columnCount = 3
        settings.columnSpacing = 18

        let geometry = try PageGeometry(settings)

        XCTAssertEqual(geometry.columnCount, 3)
        XCTAssertEqual(geometry.columnSpacing, 18, accuracy: 0.001)

        let expectedWidth =
            (
                geometry.contentSize.width
                - 36
            ) / 3

        XCTAssertEqual(
            geometry.columnWidth,
            expectedWidth,
            accuracy: 0.001
        )

        XCTAssertEqual(
            geometry.columnOriginX(for: 0),
            geometry.contentOrigin.x,
            accuracy: 0.001
        )

        XCTAssertEqual(
            geometry.columnOriginX(for: 1),
            geometry.contentOrigin.x
                + expectedWidth
                + 18,
            accuracy: 0.001
        )

        XCTAssertEqual(
            geometry.columnOriginX(for: 2),
            geometry.contentOrigin.x
                + 2
                    * (
                        expectedWidth
                        + 18
                    ),
            accuracy: 0.001
        )
    }


    func testPageLayoutCreatesColumnSizedContainer() throws {
        var settings = PageSettings()
        settings.columnCount = 3
        settings.columnSpacing = 18

        let geometry =
            try PageGeometry(
                settings
            )

        let layout =
            PageLayout(
                text:
                    NSAttributedString(
                        string:
                            "Column container"
                    )
            )

        let container =
            layout.addColumnContainer(
                geometry:
                    geometry
            )

        XCTAssertEqual(
            container.containerSize.width,
            geometry.columnWidth,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            container.containerSize.height,
            geometry.contentSize.height,
            accuracy:
                0.001
        )

        XCTAssertFalse(
            container.widthTracksTextView
        )

        XCTAssertFalse(
            container.heightTracksTextView
        )

        XCTAssertEqual(
            container.lineFragmentPadding,
            0,
            accuracy:
                0.001
        )
    }


    func testPrintLayoutDisplaysThreeFlowingColumns() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Three column print layout must flow continuously across every column and physical page. ",
                        count:
                            900
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()
        editor.layoutSubtreeIfNeeded()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertFalse(
            editor.pages.isEmpty
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            3
        )

        let geometry =
            try PageGeometry(
                settings
            )

        let primaryContainer =
            try XCTUnwrap(
                editor.pages[0].textContainer
            )

        XCTAssertEqual(
            primaryContainer.containerSize.width,
            geometry.columnWidth,
            accuracy:
                0.001
        )

        let pageNumber =
            editor.pages[0].pageNumber

        let visibleViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber == pageNumber
                        && $0.textContainer != nil
                }

        XCTAssertEqual(
            visibleViews.count,
            3
        )

        let origins =
            visibleViews
                .compactMap {
                    $0.writingOriginOverride?.x
                }
                .sorted()

        XCTAssertEqual(
            origins.count,
            3
        )

        if origins.count == 3 {
            for index in 0..<3 {
                XCTAssertEqual(
                    origins[index],
                    geometry.columnOriginX(
                        for:
                            index
                    ),
                    accuracy:
                        0.001
                )
            }
        }

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        var upperBound =
            0

        for (
            index,
            range
        ) in editor.pageRanges.enumerated() {

            if editor.pageContainerIndices[index].isEmpty {
                XCTAssertEqual(
                    range.length,
                    0
                )
                continue
            }

            XCTAssertEqual(
                range.location,
                upperBound
            )

            upperBound =
                range.upperBound
        }

        XCTAssertEqual(
            upperBound,
            text.length
        )
    }


    func testNavigationTargetsSecondaryColumnView() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Secondary column navigation must target the actual text view that owns the character. ",
                        count:
                            500
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            3
        )

        let secondContainerIndex =
            editor.pageContainerIndices[0][1]

        let thirdContainerIndex =
            editor.pageContainerIndices[0][2]

        let secondContainer =
            editor.flow.manager.textContainers[
                secondContainerIndex
            ]

        let thirdContainer =
            editor.flow.manager.textContainers[
                thirdContainerIndex
            ]

        editor.flow.manager.ensureLayout(
            for:
                secondContainer
        )

        editor.flow.manager.ensureLayout(
            for:
                thirdContainer
        )

        let secondCharacters =
            editor.flow.manager.characterRange(
                forGlyphRange:
                    editor.flow.manager.glyphRange(
                        for:
                            secondContainer
                    ),
                actualGlyphRange:
                    nil
            )

        let thirdCharacters =
            editor.flow.manager.characterRange(
                forGlyphRange:
                    editor.flow.manager.glyphRange(
                        for:
                            thirdContainer
                    ),
                actualGlyphRange:
                    nil
            )

        XCTAssertGreaterThan(
            secondCharacters.length,
            0
        )

        XCTAssertGreaterThan(
            thirdCharacters.length,
            0
        )

        let secondPoint =
            secondCharacters.location
                + max(
                    0,
                    secondCharacters.length / 2
                )

        let thirdPoint =
            thirdCharacters.location
                + max(
                    0,
                    thirdCharacters.length / 2
                )

        let secondView =
            editor.pageView(
                containing:
                    secondPoint
            )

        let thirdView =
            editor.pageView(
                containing:
                    thirdPoint
            )

        XCTAssertTrue(
            secondView.textContainer
                === secondContainer
        )

        XCTAssertTrue(
            thirdView.textContainer
                === thirdContainer
        )

        XCTAssertFalse(
            secondView
                === editor.pages[0]
        )

        XCTAssertFalse(
            thirdView
                === editor.pages[0]
        )

        let revealedSecond =
            editor.reveal(
                character:
                    secondPoint,
                focus:
                    false
            )

        let revealedThird =
            editor.reveal(
                character:
                    thirdPoint,
                focus:
                    false
            )

        XCTAssertTrue(
            revealedSecond
                === secondView
        )

        XCTAssertTrue(
            revealedThird
                === thirdView
        )
    }


    func testSecondaryColumnViewsUseSharedEditingConfiguration() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Secondary column editing ownership must stay synchronized with the primary editor. ",
                        count:
                            500
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        var configuredViews:
            [WritingTextView] = []

        editor.configureTextView = {
            view in

            configuredViews.append(
                view
            )
        }

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            3
        )

        let firstPageNumber =
            editor.pages[0].pageNumber

        let firstPageViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber == firstPageNumber
                        && $0.textContainer != nil
                }

        XCTAssertEqual(
            firstPageViews.count,
            3
        )

        let secondaryViews =
            firstPageViews.filter {
                $0 !== editor.pages[0]
            }

        XCTAssertEqual(
            secondaryViews.count,
            2
        )

        for view in secondaryViews {
            XCTAssertTrue(
                configuredViews.contains(
                    where: {
                        $0 === view
                    }
                )
            )

            XCTAssertTrue(
                view.sessionUndoManager
                    === editor.sharedUndoManager
            )

            XCTAssertTrue(
                view.textStorage
                    === editor.pages[0].textStorage
            )

            XCTAssertTrue(
                view.layoutManager
                    === editor.pages[0].layoutManager
            )
        }

        let secondary =
            try XCTUnwrap(
                secondaryViews.first
            )

        let container =
            try XCTUnwrap(
                secondary.textContainer
            )

        editor.flow.manager.ensureLayout(
            for:
                container
        )

        let characters =
            editor.flow.manager.characterRange(
                forGlyphRange:
                    editor.flow.manager.glyphRange(
                        for:
                            container
                    ),
                actualGlyphRange:
                    nil
            )

        XCTAssertGreaterThan(
            characters.length,
            0
        )

        let location =
            characters.location
                + characters.length / 2

        let destination =
            editor.pageView(
                containing:
                    location
            )

        XCTAssertTrue(
            destination === secondary
        )
    }


    func testNextColumnSectionBreakAdvancesToNextColumn() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let prefix =
            String(
                repeating:
                    "Before column break. ",
                count:
                    8
            )
                + "\n"

        let breakLocation =
            (prefix as NSString).length

        let suffix =
            String(
                repeating:
                    "After column break. ",
                count:
                    90
            )

        let text =
            NSAttributedString(
                string:
                    prefix + suffix,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        var nextColumnSection =
            DocumentSection(
                location:
                    breakLocation,
                page:
                    settings
            )

        nextColumnSection.breakType =
            .nextColumn

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                ),
                nextColumnSection
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertTrue(
            editor.flow.sectionBreakLocations.contains(
                breakLocation
            )
        )

        XCTAssertGreaterThanOrEqual(
            editor.pageContainerIndices[0].count,
            2
        )

        let firstContainerIndex =
            editor.pageContainerIndices[0][0]

        let secondContainerIndex =
            editor.pageContainerIndices[0][1]

        let firstContainer =
            editor.flow.manager.textContainers[
                firstContainerIndex
            ]

        let secondContainer =
            editor.flow.manager.textContainers[
                secondContainerIndex
            ]

        editor.flow.manager.ensureLayout(
            for:
                secondContainer
        )

        let firstCharacters =
            editor.flow.manager.characterRange(
                forGlyphRange:
                    editor.flow.manager.glyphRange(
                        for:
                            firstContainer
                    ),
                actualGlyphRange:
                    nil
            )

        let secondCharacters =
            editor.flow.manager.characterRange(
                forGlyphRange:
                    editor.flow.manager.glyphRange(
                        for:
                            secondContainer
                    ),
                actualGlyphRange:
                    nil
            )

        XCTAssertLessThanOrEqual(
            NSMaxRange(
                firstCharacters
            ),
            breakLocation
        )

        XCTAssertEqual(
            secondCharacters.location,
            breakLocation
        )

        XCTAssertGreaterThan(
            secondCharacters.length,
            0
        )

        let destination =
            editor.pageView(
                containing:
                    min(
                        text.length - 1,
                        breakLocation + 1
                    )
            )

        XCTAssertTrue(
            destination.textContainer
                === secondContainer
        )
    }


    func testChangingColumnSettingsRepaginatesExistingPages() throws {
        var singleColumn = PageSettings()
        singleColumn.topMargin = 54
        singleColumn.bottomMargin = 54
        singleColumn.leftMargin = 54
        singleColumn.rightMargin = 54
        singleColumn.columnCount = 1
        singleColumn.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Changing section column settings must rebuild the TextKit containers and repaginate the manuscript without losing text. ",
                        count:
                            900
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                singleColumn,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        singleColumn
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            1
        )

        let originalPageCount =
            editor.pages.count

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        var threeColumn =
            singleColumn

        threeColumn.columnCount =
            3

        threeColumn.columnSpacing =
            18

        editor.configure(
            printLayout:
                true,
            settings:
                threeColumn,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        threeColumn
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()
        editor.layoutSubtreeIfNeeded()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            3
        )

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        XCTAssertNotEqual(
            editor.pages.count,
            originalPageCount
        )

        let geometry =
            try PageGeometry(
                threeColumn
            )

        let firstPageNumber =
            editor.pages[0]
                .pageNumber

        let firstPageViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber
                        == firstPageNumber
                        && $0.textContainer != nil
                }

        XCTAssertEqual(
            firstPageViews.count,
            3
        )

        let origins =
            firstPageViews
                .compactMap {
                    $0.writingOriginOverride?.x
                }
                .sorted()

        XCTAssertEqual(
            origins.count,
            3
        )

        if origins.count == 3 {
            for index in 0..<3 {
                XCTAssertEqual(
                    origins[index],
                    geometry.columnOriginX(
                        for:
                            index
                    ),
                    accuracy:
                        0.001
                )
            }
        }

        var previousUpperBound =
            0

        for (
            index,
            range
        ) in editor.pageRanges.enumerated() {

            if editor.pageContainerIndices[index].isEmpty {
                XCTAssertEqual(
                    range.length,
                    0
                )
                continue
            }

            XCTAssertEqual(
                range.location,
                previousUpperBound
            )

            previousUpperBound =
                range.upperBound
        }

        XCTAssertEqual(
            previousUpperBound,
            text.length
        )

        editor.configure(
            printLayout:
                true,
            settings:
                singleColumn,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        singleColumn
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()
        editor.layoutSubtreeIfNeeded()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        XCTAssertEqual(
            editor.pages.count,
            originalPageCount
        )

        let revertedFirstPageNumber =
            editor.pages[0]
                .pageNumber

        let revertedViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber
                        == revertedFirstPageNumber
                        && $0.textContainer != nil
                }

        XCTAssertEqual(
            revertedViews.count,
            1
        )
    }


    func testThreeColumnPDFMatchesPrintLayoutPagination() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "PDF export must use the same three-column physical-page flow as Print Layout. ",
                        count:
                            900
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThan(
            editor.pages.count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                settings,
                            sections: [
                                DocumentSection(
                                    location:
                                        0,
                                    page:
                                        settings
                                )
                            ]
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        let firstPage =
            try XCTUnwrap(
                pdf.page(
                    at:
                        0
                )
            )

        let extracted =
            firstPage.string
                ?? ""

        XCTAssertFalse(
            extracted.isEmpty
        )
    }


    func testSectionTransitionsUseDifferentColumnCounts() throws {
        var singleColumn = PageSettings()
        singleColumn.topMargin = 54
        singleColumn.bottomMargin = 54
        singleColumn.leftMargin = 54
        singleColumn.rightMargin = 54
        singleColumn.columnCount = 1
        singleColumn.columnSpacing = 18

        var threeColumn =
            singleColumn

        threeColumn.columnCount =
            3

        let firstText =
            String(
                repeating:
                    "First section remains single column. ",
                count:
                    55
            )
            + "\n"

        let secondText =
            String(
                repeating:
                    "Second section must use three independent flowing columns. ",
                count:
                    260
            )
            + "\n"

        let thirdText =
            String(
                repeating:
                    "Third section returns to a single column. ",
                count:
                    80
            )

        let secondLocation =
            (firstText as NSString).length

        let thirdLocation =
            (
                firstText
                + secondText
                as NSString
            ).length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + secondText
                    + thirdText,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )


        var secondSection =
            DocumentSection(
                location:
                    secondLocation,
                page:
                    threeColumn
            )

        secondSection.breakType =
            .nextPage

        var thirdSection =
            DocumentSection(
                location:
                    thirdLocation,
                page:
                    singleColumn
            )

        thirdSection.breakType =
            .nextPage

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                singleColumn,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        singleColumn
                ),
                secondSection,
                thirdSection
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()
        editor.layoutSubtreeIfNeeded()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pageRanges.last?.upperBound,
            text.length
        )

        let secondPageIndex =
            try XCTUnwrap(
                editor.pageRanges
                    .indices
                    .first {
                        index in

                        let range =
                            editor.pageRanges[index]

                        return range.length > 0
                            && range.location
                                <= secondLocation
                            && secondLocation
                                < range.upperBound
                    }
            )

        let thirdPageIndex =
            try XCTUnwrap(
                editor.pageRanges
                    .indices
                    .first {
                        index in

                        let range =
                            editor.pageRanges[index]

                        return range.length > 0
                            && range.location
                                <= thirdLocation
                            && thirdLocation
                                < range.upperBound
                    }
            )

        XCTAssertGreaterThan(
            secondPageIndex,
            0
        )

        XCTAssertGreaterThan(
            thirdPageIndex,
            secondPageIndex
        )

        XCTAssertEqual(
            editor.pageContainerIndices[
                secondPageIndex
            ].count,
            3
        )

        XCTAssertEqual(
            editor.pageContainerIndices[
                thirdPageIndex
            ].count,
            1
        )

        let secondGeometry =
            try editor.pageGeometry(
                forCharacter:
                    secondLocation
            )

        let thirdGeometry =
            try editor.pageGeometry(
                forCharacter:
                    thirdLocation
            )

        XCTAssertEqual(
            secondGeometry.columnCount,
            3
        )

        XCTAssertEqual(
            thirdGeometry.columnCount,
            1
        )

        let secondViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber
                        == editor.pages[
                            secondPageIndex
                        ].pageNumber
                        && $0.textContainer != nil
                }

        let thirdViews =
            editor.subviews
                .compactMap {
                    $0 as? WritingTextView
                }
                .filter {
                    $0.pageNumber
                        == editor.pages[
                            thirdPageIndex
                        ].pageNumber
                        && $0.textContainer != nil
                }

        XCTAssertEqual(
            secondViews.count,
            3
        )

        XCTAssertEqual(
            thirdViews.count,
            1
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                singleColumn,
                            sections: [
                                DocumentSection(
                                    location:
                                        0,
                                    page:
                                        singleColumn
                                ),
                                secondSection,
                                thirdSection
                            ]
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        var previousUpperBound =
            0

        for (
            index,
            range
        ) in editor.pageRanges.enumerated() {

            if editor.pageContainerIndices[
                index
            ].isEmpty {
                XCTAssertEqual(
                    range.length,
                    0
                )
                continue
            }

            XCTAssertEqual(
                range.location,
                previousUpperBound
            )

            previousUpperBound =
                range.upperBound
        }

        XCTAssertEqual(
            previousUpperBound,
            text.length
        )
    }


    func testControllerNavigationTargetsCaretInsideSecondaryColumn() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Caret navigation must reveal and activate the exact secondary column that owns the requested character. ",
                        count:
                            500
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let canvas =
            PaginatedEditor(
                text:
                    text
            )

        canvas.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        canvas.finishPagination()
        canvas.layoutSubtreeIfNeeded()

        XCTAssertNil(
            canvas.lastLayoutError
        )

        XCTAssertTrue(
            canvas.layoutComplete
        )

        XCTAssertEqual(
            canvas.pageContainerIndices[0].count,
            3
        )

        let secondContainerIndex =
            canvas.pageContainerIndices[0][1]

        let secondContainer =
            canvas.flow.manager.textContainers[
                secondContainerIndex
            ]

        canvas.flow.manager.ensureLayout(
            for:
                secondContainer
        )

        let secondCharacters =
            canvas.flow.manager.characterRange(
                forGlyphRange:
                    canvas.flow.manager.glyphRange(
                        for:
                            secondContainer
                    ),
                actualGlyphRange:
                    nil
            )

        XCTAssertGreaterThan(
            secondCharacters.length,
            4
        )

        let target =
            NSRange(
                location:
                    secondCharacters.location + 3,
                length:
                    0
            )

        let expectedView =
            canvas.pageView(
                containing:
                    target.location
            )

        XCTAssertTrue(
            expectedView.textContainer
                === secondContainer
        )

        XCTAssertFalse(
            expectedView
                === canvas.pages[0]
        )

        let revealed =
            canvas.reveal(
                character:
                    target.location,
                focus:
                    false
            )

        XCTAssertTrue(
            revealed
                === expectedView
        )

        let controller =
            EditorController()

        controller.attach(
            canvas.firstView
        )

        controller.navigate(
            to:
                target
        )

        XCTAssertTrue(
            controller.textView
                === expectedView
        )

        XCTAssertEqual(
            controller.selection,
            target
        )

        XCTAssertEqual(
            expectedView.selectedRange(),
            target
        )
    }


    func testMultiColumnPaginationIgnoresZoomAndViewportChanges() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 63
        settings.rightMargin = 63
        settings.columnCount = 3
        settings.columnSpacing = 18

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Multi-column physical pagination must remain independent of visual zoom and editor viewport width. ",
                        count:
                            700
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                14
                        )
                ]
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    settings
            )
        ]

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        let originalPageCount =
            editor.pages.count

        let originalRanges =
            editor.pageRanges

        let originalMappings =
            editor.pageContainerIndices
                .map {
                    $0.count
                }

        XCTAssertGreaterThan(
            originalPageCount,
            1
        )

        XCTAssertTrue(
            originalMappings
                .filter {
                    $0 > 0
                }
                .allSatisfy {
                    $0 == 3
                }
        )

        for configuration in [
            (0.65, CGFloat(520)),
            (1.8, CGFloat(1600)),
            (1.25, CGFloat(760)),
            (1.0, CGFloat(1000))
        ] {
            editor.configure(
                printLayout:
                    true,
                settings:
                    settings,
                sections:
                    sections,
                zoom:
                    configuration.0,
                viewportWidth:
                    configuration.1
            )

            editor.finishPagination()

            XCTAssertNil(
                editor.lastLayoutError
            )

            XCTAssertTrue(
                editor.layoutComplete
            )

            XCTAssertEqual(
                editor.pages.count,
                originalPageCount
            )

            XCTAssertEqual(
                editor.pageRanges,
                originalRanges
            )

            XCTAssertEqual(
                editor.pageContainerIndices
                    .map {
                        $0.count
                    },
                originalMappings
            )
        }
    }

    func testMultiColumnVisibleViewsMatchTwoAndFourColumnGeometry() throws {
        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Visible column views must follow the active section geometry exactly. ",
                        count:
                            500
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        for count in [
            2,
            4
        ] {
            var settings =
                PageSettings()

            settings.topMargin =
                54

            settings.bottomMargin =
                54

            settings.leftMargin =
                54

            settings.rightMargin =
                54

            settings.columnCount =
                count

            settings.columnSpacing =
                18

            let editor =
                PaginatedEditor(
                    text:
                        text
                )

            editor.configure(
                printLayout:
                    true,
                settings:
                    settings,
                sections: [
                    DocumentSection(
                        location:
                            0,
                        page:
                            settings
                    )
                ],
                zoom:
                    1,
                viewportWidth:
                    1000
            )

            editor.finishPagination()
            editor.layoutSubtreeIfNeeded()

            XCTAssertNil(
                editor.lastLayoutError
            )

            XCTAssertTrue(
                editor.layoutComplete
            )

            XCTAssertEqual(
                editor.pageContainerIndices[0].count,
                count
            )

            let geometry =
                try PageGeometry(
                    settings
                )

            let pageNumber =
                editor.pages[0]
                    .pageNumber

            let views =
                editor.subviews
                    .compactMap {
                        $0 as? WritingTextView
                    }
                    .filter {
                        $0.pageNumber
                            == pageNumber
                            && $0.textContainer
                                != nil
                    }

            XCTAssertEqual(
                views.count,
                count
            )

            let origins =
                views
                    .compactMap {
                        $0.writingOriginOverride?.x
                    }
                    .sorted()

            XCTAssertEqual(
                origins.count,
                count
            )

            if origins.count == count {
                for index
                    in 0..<count {

                    XCTAssertEqual(
                        origins[index],
                        geometry.columnOriginX(
                            for:
                                index
                        ),
                        accuracy:
                            0.001
                    )

                    let containerIndex =
                        editor.pageContainerIndices[0][
                            index
                        ]

                    let container =
                        editor.flow.manager.textContainers[
                            containerIndex
                        ]

                    XCTAssertEqual(
                        container.containerSize.width,
                        geometry.columnWidth,
                        accuracy:
                            0.001
                    )
                }
            }

            XCTAssertEqual(
                editor.pageRanges.last?
                    .upperBound,
                text.length
            )
        }
    }

    func testMultiColumnPDFParityAlsoHoldsForTwoColumns() throws {
        var settings =
            PageSettings()

        settings.topMargin =
            54

        settings.bottomMargin =
            54

        settings.leftMargin =
            54

        settings.rightMargin =
            54

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let text =
            NSAttributedString(
                string:
                    String(
                        repeating:
                            "Two-column PDF export and Print Layout must consume the same manuscript stream and create the same physical page count. ",
                        count:
                            850
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    settings
            )
        ]

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThan(
            editor.pages.count,
            1
        )

        XCTAssertTrue(
            editor.pageContainerIndices
                .filter {
                    !$0.isEmpty
                }
                .allSatisfy {
                    $0.count == 2
                }
        )

        XCTAssertEqual(
            editor.pageRanges.last?
                .upperBound,
            text.length
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                settings,
                            sections:
                                sections
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        XCTAssertFalse(
            try XCTUnwrap(
                pdf.page(
                    at:
                        0
                )
            )
            .string?
            .isEmpty
            ?? true
        )
    }


    func testPageBreakBeforeStartsParagraphOnNextPhysicalPage() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "First paragraph stays on page one.\n"
                    + "Second paragraph must begin on page two.",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let secondLocation =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "Second paragraph"
            )
            .location

        XCTAssertNotEqual(
            secondLocation,
            NSNotFound
        )

        let secondRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            secondLocation,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterPageBreakBefore,
            value:
                true,
            range:
                secondRange
        )

        var settings =
            PageSettings()

        settings.topMargin =
            54

        settings.bottomMargin =
            54

        settings.leftMargin =
            54

        settings.rightMargin =
            54

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThanOrEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageRanges[0]
                .upperBound,
            secondLocation
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            secondLocation
        )

        XCTAssertTrue(
            editor.pageRanges[1]
                .contains(
                    secondLocation
                )
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                settings,
                            sections: [
                                DocumentSection(
                                    location:
                                        0,
                                    page:
                                        settings
                                )
                            ]
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    0
            )?
            .string?
            .contains(
                "First paragraph"
            )
            ?? false
        )

        XCTAssertFalse(
            pdf.page(
                at:
                    0
            )?
            .string?
            .contains(
                "Second paragraph"
            )
            ?? true
        )

        XCTAssertTrue(
            pdf.page(
                at:
                    1
            )?
            .string?
            .contains(
                "Second paragraph"
            )
            ?? false
        )
    }


    func testPageBreakBeforeSkipsRemainingColumnsAndStartsNextPhysicalPage() throws {
        func normalizedPDFText(
            _ value: String?
        ) -> String {
            (value ?? "")
                .components(
                    separatedBy:
                        .whitespacesAndNewlines
                )
                .filter {
                    !$0.isEmpty
                }
                .joined(
                    separator:
                        " "
                )
        }

        var settings =
            PageSettings()

        settings.topMargin =
            54

        settings.bottomMargin =
            54

        settings.leftMargin =
            54

        settings.rightMargin =
            54

        settings.columnCount =
            3

        settings.columnSpacing =
            18

        let text =
            NSMutableAttributedString(
                string:
                    "Short first paragraph stays in column one.\n"
                    + String(
                        repeating:
                            "This paragraph has Word page-break-before and must begin on the next physical page, never in column two or column three of the first page. ",
                        count:
                            140
                    ),
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let secondLocation =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "This paragraph has Word page-break-before"
            )
            .location

        XCTAssertNotEqual(
            secondLocation,
            NSNotFound
        )

        let secondRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            secondLocation,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterPageBreakBefore,
            value:
                true,
            range:
                secondRange
        )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            sections: [
                DocumentSection(
                    location:
                        0,
                    page:
                        settings
                )
            ],
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()
        editor.layoutSubtreeIfNeeded()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThanOrEqual(
            editor.pages.count,
            2
        )

        XCTAssertEqual(
            editor.pageContainerIndices[0].count,
            1
        )

        XCTAssertEqual(
            editor.pageRanges[0]
                .upperBound,
            secondLocation
        )

        XCTAssertEqual(
            editor.pageRanges[1]
                .location,
            secondLocation
        )

        let destination =
            editor.pageView(
                containing:
                    secondLocation
            )

        XCTAssertTrue(
            destination
                === editor.pages[1]
        )

        XCTAssertFalse(
            destination
                === editor.pages[0]
        )

        XCTAssertEqual(
            editor.pageContainerIndices[1].count,
            3
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                settings,
                            sections: [
                                DocumentSection(
                                    location:
                                        0,
                                    page:
                                        settings
                                )
                            ]
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )

        let firstPDFPage =
            normalizedPDFText(
                pdf.page(
                    at:
                        0
                )?
                .string
            )

        let secondPDFPage =
            normalizedPDFText(
                pdf.page(
                    at:
                        1
                )?
                .string
            )

        XCTAssertTrue(
            firstPDFPage.contains(
                "Short first paragraph stays in column one."
            )
        )

        XCTAssertFalse(
            firstPDFPage.contains(
                "This paragraph has Word page-break-before"
            )
        )

        XCTAssertTrue(
            secondPDFPage.contains(
                "This paragraph has Word page-break-before"
            )
        )
    }


    func testKeepLinesTogetherMovesSplitParagraphToNextPage() throws {
        var settings =
            PageSettings()

        settings.topMargin = 72
        settings.bottomMargin = 72
        settings.leftMargin = 72
        settings.rightMargin = 72

        let paragraph =
            String(
                repeating:
                    "Keep-lines paragraph content must remain together when there is room for the whole paragraph on the following physical page. ",
                count:
                    5
            )
            + "\n"

        let source =
            Array(
                repeating:
                    paragraph,
                count:
                    45
            )
            .joined()

        let baselineText =
            NSAttributedString(
                string:
                    source,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let baseline =
            PaginatedEditor(
                text:
                    baselineText
            )

        baseline.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        baseline.finishPagination()

        XCTAssertNil(
            baseline.lastLayoutError
        )

        let string =
            source
                as NSString

        var splitParagraph:
            NSRange?

        for pageRange
            in baseline.pageRanges.dropLast() {

            let boundary =
                NSMaxRange(
                    pageRange
                )

            guard
                boundary > 0,
                boundary < string.length
            else {
                continue
            }

            let paragraphRange =
                string.paragraphRange(
                    for:
                        NSRange(
                            location:
                                boundary - 1,
                            length:
                                0
                        )
                )

            if boundary
                < NSMaxRange(
                    paragraphRange
                ),
               paragraphRange.location
                > pageRange.location {

                splitParagraph =
                    paragraphRange
                break
            }
        }

        let target =
            try XCTUnwrap(
                splitParagraph
            )

        let protected =
            NSMutableAttributedString(
                attributedString:
                    baselineText
            )

        protected.addAttribute(
            .boldWriterKeepLinesTogether,
            value:
                true,
            range:
                target
        )

        let editor =
            PaginatedEditor(
                text:
                    protected
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        let containingPages =
            editor.pageRanges.filter {
                NSIntersectionRange(
                    $0,
                    target
                )
                .length > 0
            }

        XCTAssertEqual(
            containingPages.count,
            1
        )

        let containing =
            try XCTUnwrap(
                containingPages.first
            )

        XCTAssertLessThanOrEqual(
            containing.location,
            target.location
        )

        XCTAssertGreaterThanOrEqual(
            NSMaxRange(
                containing
            ),
            NSMaxRange(
                target
            )
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                protected,
                            settings:
                                settings
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )
    }

    func testKeepWithNextMovesParagraphBesideFollowingParagraph() throws {
        var settings =
            PageSettings()

        settings.topMargin = 72
        settings.bottomMargin = 72
        settings.leftMargin = 72
        settings.rightMargin = 72

        let paragraph =
            "Keep-with-next short paragraph used to create stable page boundaries for Word-compatible pagination behavior.\n"

        let source =
            Array(
                repeating:
                    paragraph,
                count:
                    180
            )
            .joined()

        let baselineText =
            NSAttributedString(
                string:
                    source,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let baseline =
            PaginatedEditor(
                text:
                    baselineText
            )

        baseline.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        baseline.finishPagination()

        XCTAssertNil(
            baseline.lastLayoutError
        )

        let string =
            source
                as NSString

        var keepParagraph:
            NSRange?

        var followingParagraph:
            NSRange?

        for pageIndex
            in baseline.pageRanges.indices.dropLast() {

            let pageRange =
                baseline.pageRanges[
                    pageIndex
                ]

            let boundary =
                NSMaxRange(
                    pageRange
                )

            guard
                boundary > pageRange.location,
                boundary < string.length
            else {
                continue
            }

            let previous =
                string.paragraphRange(
                    for:
                        NSRange(
                            location:
                                boundary - 1,
                            length:
                                0
                        )
                )

            guard
                NSMaxRange(
                    previous
                ) == boundary,
                previous.location
                    > pageRange.location
            else {
                continue
            }

            let next =
                string.paragraphRange(
                    for:
                        NSRange(
                            location:
                                boundary,
                            length:
                                0
                        )
                )

            guard
                next.length > 0
            else {
                continue
            }

            keepParagraph =
                previous

            followingParagraph =
                next

            break
        }

        let keep =
            try XCTUnwrap(
                keepParagraph
            )

        let next =
            try XCTUnwrap(
                followingParagraph
            )

        let protected =
            NSMutableAttributedString(
                attributedString:
                    baselineText
            )

        protected.addAttribute(
            .boldWriterKeepWithNext,
            value:
                true,
            range:
                keep
        )

        let editor =
            PaginatedEditor(
                text:
                    protected
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        let keepPageIndex =
            try XCTUnwrap(
                editor.pageRanges.firstIndex {
                    range in

                    keep.location >= range.location
                    && keep.location < NSMaxRange(
                        range
                    )
                }
            )

        let nextPageIndex =
            try XCTUnwrap(
                editor.pageRanges.firstIndex {
                    range in

                    next.location >= range.location
                    && next.location < NSMaxRange(
                        range
                    )
                }
            )

        XCTAssertEqual(
            keepPageIndex,
            nextPageIndex
        )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                protected,
                            settings:
                                settings
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )
    }


    func testWidowControlMovesOneLineOrphanToNextPage() throws {
        var settings =
            PageSettings()

        settings.topMargin = 72
        settings.bottomMargin = 72
        settings.leftMargin = 72
        settings.rightMargin = 72

        let filler =
            Array(
                repeating:
                    "Filler line for widow control boundary.\n",
                count:
                    31
            )
            .joined()

        let protectedParagraph =
            String(
                repeating:
                    "Widow control must prevent a single first line from being stranded at the bottom of a page. ",
                count:
                    10
            )
            + "\n"

        let source =
            filler
            + protectedParagraph
            + Array(
                repeating:
                    "Trailing paragraph after widow control test.\n",
                count:
                    20
            )
            .joined()

        let text =
            NSMutableAttributedString(
                string:
                    source,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let protectedLocation =
            (
                source
                    as NSString
            )
            .range(
                of:
                    protectedParagraph
            )
            .location

        XCTAssertNotEqual(
            protectedLocation,
            NSNotFound
        )

        let protectedRange =
            (
                source
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            protectedLocation,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterWidowControl,
            value:
                true,
            range:
                protectedRange
        )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        let intersecting =
            editor.pageRanges
                .enumerated()
                .filter {
                    _, range in

                    NSIntersectionRange(
                        range,
                        protectedRange
                    )
                    .length > 0
                }

        XCTAssertGreaterThanOrEqual(
            intersecting.count,
            1
        )

        XCTAssertLessThanOrEqual(
            intersecting.count,
            2
        )

        if intersecting.count == 2 {
            let firstRange =
                NSIntersectionRange(
                    intersecting[0].element,
                    protectedRange
                )

            let secondRange =
                NSIntersectionRange(
                    intersecting[1].element,
                    protectedRange
                )

            let layout =
                editor.flow.manager

            let firstGlyphs =
                layout.glyphRange(
                    forCharacterRange:
                        firstRange,
                    actualCharacterRange:
                        nil
                )

            let secondGlyphs =
                layout.glyphRange(
                    forCharacterRange:
                        secondRange,
                    actualCharacterRange:
                        nil
                )

            var firstLines = 0
            var secondLines = 0

            layout.enumerateLineFragments(
                forGlyphRange:
                    firstGlyphs
            ) {
                _,
                _,
                _,
                range,
                _ in

                if range.length > 0 {
                    firstLines += 1
                }
            }

            layout.enumerateLineFragments(
                forGlyphRange:
                    secondGlyphs
            ) {
                _,
                _,
                _,
                range,
                _ in

                if range.length > 0 {
                    secondLines += 1
                }
            }

            XCTAssertGreaterThanOrEqual(
                firstLines,
                2
            )

            XCTAssertGreaterThanOrEqual(
                secondLines,
                2
            )
        }

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        PDFExporter.data(
                            from:
                                text,
                            settings:
                                settings
                        )
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            editor.pages.count
        )
    }


    func testViewingModeDisablesEditingWithoutDisablingSelection() {
        _ = NSApplication.shared

        let editor =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "Viewing mode"
                    )
            )

        XCTAssertTrue(
            editor.firstView.isEditable
        )

        XCTAssertTrue(
            editor.firstView.isSelectable
        )

        editor.setEditingEnabled(
            false
        )

        XCTAssertFalse(
            editor.firstView.isEditable
        )

        XCTAssertTrue(
            editor.firstView.isSelectable
        )

        editor.setEditingEnabled(
            true
        )

        XCTAssertTrue(
            editor.firstView.isEditable
        )

        XCTAssertTrue(
            editor.firstView.isSelectable
        )
    }



    func testNonPrintingCharactersToggleLayoutManagerVisibility() {
        _ = NSApplication.shared

        let editor =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "One\tTwo\nThree"
                    )
            )

        XCTAssertFalse(
            editor.firstView
                .layoutManager?
                .showsInvisibleCharacters
                ?? true
        )

        editor.setShowsInvisibleCharacters(
            true
        )

        XCTAssertTrue(
            editor.firstView
                .layoutManager?
                .showsInvisibleCharacters
                ?? false
        )

        editor.setShowsInvisibleCharacters(
            false
        )

        XCTAssertFalse(
            editor.firstView
                .layoutManager?
                .showsInvisibleCharacters
                ?? true
        )
    }



    func testLineNumberVisibilityPropagatesWithoutChangingDocumentText() {
        _ = NSApplication.shared

        let original =
            NSAttributedString(
                string:
                    "First line\nSecond line\nThird line"
            )

        let editor =
            PaginatedEditor(
                text:
                    original
            )

        XCTAssertFalse(
            editor.firstView
                .showsLineNumbers
        )

        editor.setShowsLineNumbers(
            true
        )

        XCTAssertTrue(
            editor.firstView
                .showsLineNumbers
        )

        XCTAssertEqual(
            editor.firstView.string,
            original.string
        )

        editor.setShowsLineNumbers(
            false
        )

        XCTAssertFalse(
            editor.firstView
                .showsLineNumbers
        )

        XCTAssertEqual(
            editor.firstView.string,
            original.string
        )
    }


}


extension WritingInterfaceTests {
    func testPageSettingsHeaderFooterEdgeDistancesPreserveLegacyFallback()
        throws
    {
        var legacy =
            PageSettings()

        legacy.topMargin =
            80

        legacy.bottomMargin =
            100

        XCTAssertNil(
            legacy.headerDistance
        )

        XCTAssertNil(
            legacy.footerDistance
        )

        XCTAssertEqual(
            legacy.effectiveHeaderDistance,
            40
        )

        XCTAssertEqual(
            legacy.effectiveFooterDistance,
            50
        )

        var word =
            legacy

        word.headerDistance =
            18

        word.footerDistance =
            54

        XCTAssertEqual(
            word.effectiveHeaderDistance,
            18
        )

        XCTAssertEqual(
            word.effectiveFooterDistance,
            54
        )

        XCTAssertFalse(
            word.usesLegacyFooterLayout
        )

        _ =
            try PageGeometry(
                word
            )
    }
}

extension WritingInterfaceTests {
    func testPageGeometryResolvesWordGutterAndMirroredFacingPages()
        throws
    {
        var settings =
            PageSettings()

        settings.leftMargin =
            90

        settings.rightMargin =
            54

        settings.topMargin =
            72

        settings.bottomMargin =
            72

        settings.gutter =
            18

        settings.mirrorMargins =
            true

        let base =
            try PageGeometry(
                settings
            )

        let odd =
            base.resolvingPhysicalPage(
                1
            )

        let even =
            base.resolvingPhysicalPage(
                2
            )

        XCTAssertEqual(
            odd.contentOrigin.x,
            108,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            even.contentOrigin.x,
            54,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            odd.contentSize.width,
            even.contentSize.width,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            odd.contentSize.width,
            450,
            accuracy:
                0.001
        )

        var ordinary =
            settings

        ordinary.mirrorMargins =
            false

        let ordinaryGeometry =
            try PageGeometry(
                ordinary
            )
            .resolvingPhysicalPage(
                2
            )

        XCTAssertEqual(
            ordinaryGeometry.contentOrigin.x,
            108,
            accuracy:
                0.001
        )
    }
}



extension WritingInterfaceTests {
    func testPageGeometryResolvesWordGutterAtTopWithFacingPages()
        throws
    {
        var settings =
            PageSettings()

        settings.leftMargin =
            90

        settings.rightMargin =
            54

        settings.topMargin =
            72

        settings.bottomMargin =
            72

        settings.gutter =
            18

        settings.gutterAtTop =
            true

        settings.mirrorMargins =
            true

        let base =
            try PageGeometry(
                settings
            )

        let odd =
            base.resolvingPhysicalPage(
                1
            )

        let even =
            base.resolvingPhysicalPage(
                2
            )

        XCTAssertEqual(
            odd.contentOrigin.x,
            90,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            even.contentOrigin.x,
            54,
            accuracy:
                0.001,
            "Mirror margins must still swap physical inside/outside margins."
        )

        XCTAssertEqual(
            odd.contentOrigin.y,
            90,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            even.contentOrigin.y,
            90,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            odd.contentSize.width,
            468,
            accuracy:
                0.001,
            "A top gutter must not reduce printable width."
        )

        XCTAssertEqual(
            even.contentSize.width,
            468,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            odd.contentSize.height,
            630,
            accuracy:
                0.001,
            "A top gutter must reduce printable height."
        )

        XCTAssertEqual(
            even.contentSize.height,
            630,
            accuracy:
                0.001
        )
    }
}


extension WritingInterfaceTests {
    func testPageGeometryResolvesWordVerticalPageAlignment()
        throws
    {
        var settings =
            PageSettings()

        let usedHeight:
            CGFloat = 200

        let top =
            try PageGeometry(
                settings
            )

        XCTAssertEqual(
            top.verticalBodyOffset(
                usedHeight:
                    usedHeight
            ),
            0,
            accuracy:
                0.001
        )

        settings.verticalPageAlignment =
            .center

        let centered =
            try PageGeometry(
                settings
            )

        XCTAssertEqual(
            centered.verticalBodyOffset(
                usedHeight:
                    usedHeight
            ),
            224,
            accuracy:
                0.001
        )

        settings.verticalPageAlignment =
            .bottom

        let bottom =
            try PageGeometry(
                settings
            )

        XCTAssertEqual(
            bottom.verticalBodyOffset(
                usedHeight:
                    usedHeight
            ),
            448,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            bottom.verticalBodyOffset(
                usedHeight:
                    1_000
            ),
            0,
            accuracy:
                0.001,
            "A full or overflowing page must not receive a negative or extra vertical offset."
        )

        XCTAssertEqual(
            bottom.verticalBodyOffset(
                usedHeight:
                    200,
                availableHeight:
                    600
            ),
            400,
            accuracy:
                0.001,
            "Reserved footnote space must reduce the body area used for bottom alignment."
        )
    }
}


extension WritingInterfaceTests {
    func testWordVerticalJustificationEligibilityUsesFullTextKitPagesOnly()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        // w:vAlign='both' must never be implemented as a whole-page
        // center/bottom translation.
        XCTAssertEqual(
            geometry.verticalBodyOffset(
                usedHeight:
                    200,
                availableHeight:
                    400
            ),
            0,
            accuracy:
                0.001
        )

        let lines =
            (1...8)
            .map {
                "VERTICAL JUSTIFICATION LINE \($0)"
            }
            .joined(
                separator:
                    "\n"
            )

        let storage =
            NSTextStorage(
                string:
                    lines,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let pageSize =
            NSSize(
                width:
                    240,
                height:
                    88
            )

        let first =
            NSTextContainer(
                size:
                    pageSize
            )

        first.lineFragmentPadding =
            0

        let second =
            NSTextContainer(
                size:
                    pageSize
            )

        second.lineFragmentPadding =
            0

        manager.addTextContainer(
            first
        )

        manager.addTextContainer(
            second
        )

        manager.ensureLayout(
            for:
                first
        )

        manager.ensureLayout(
            for:
                second
        )

        let firstGlyphs =
            manager.glyphRange(
                for:
                    first
            )

        let secondGlyphs =
            manager.glyphRange(
                for:
                    second
            )

        XCTAssertGreaterThan(
            firstGlyphs.length,
            0
        )

        XCTAssertGreaterThan(
            secondGlyphs.length,
            0,
            "The controlled fixture must overflow into a second page."
        )

        let totalGlyphs =
            manager.numberOfGlyphs

        XCTAssertLessThan(
            NSMaxRange(
                firstGlyphs
            ),
            totalGlyphs,
            "The first TextKit page must be a full/overflow page."
        )

        XCTAssertEqual(
            NSMaxRange(
                secondGlyphs
            ),
            totalGlyphs,
            "The second TextKit page must be the partial final page."
        )

        func lineCount(
            in container:
                NSTextContainer,
            glyphs:
                NSRange
        ) -> Int {
            var count =
                0

            manager.enumerateLineFragments(
                forGlyphRange:
                    glyphs
            ) {
                _,
                _,
                textContainer,
                _,
                _ in

                guard
                    textContainer
                        === container
                else {
                    return
                }

                count +=
                    1
            }

            return count
        }

        let firstLines =
            lineCount(
                in:
                    first,
                glyphs:
                    firstGlyphs
            )

        let secondLines =
            lineCount(
                in:
                    second,
                glyphs:
                    secondGlyphs
            )

        XCTAssertGreaterThan(
            firstLines,
            1
        )

        XCTAssertGreaterThan(
            secondLines,
            0
        )

        let firstUsed =
            manager.usedRect(
                for:
                    first
            )
            .height

        let secondUsed =
            manager.usedRect(
                for:
                    second
            )
            .height

        XCTAssertLessThan(
            firstUsed,
            pageSize.height,
            "The fixture must leave measurable residual vertical space on the overflow page."
        )

        let firstExpansion =
            geometry
                .verticalJustificationInterparagraphExpansion(
                    usedHeight:
                        firstUsed,
                    availableHeight:
                        pageSize.height,
                    paragraphCount:
                        firstLines,
                    isEligiblePage:
                        true
                )

        XCTAssertGreaterThan(
            firstExpansion,
            0,
            "A full w:vAlign='both' page must expose residual height for later line-fragment distribution."
        )

        let finalExpansion =
            geometry
                .verticalJustificationInterparagraphExpansion(
                    usedHeight:
                        secondUsed,
                    availableHeight:
                        pageSize.height,
                    paragraphCount:
                        secondLines,
                    isEligiblePage:
                        false
                )

        XCTAssertEqual(
            finalExpansion,
            0,
            accuracy:
                0.001,
            "An explicitly ineligible page must receive no paragraph redistribution."
        )
    }
}


extension WritingInterfaceTests {
    func testWordVerticalJustificationMutatesRealTextKitGeometry()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let paragraphOne =
            Array(
                repeating:
                    "FIRST PARAGRAPH WRAPS ACROSS VISUAL LINES.",
                count:
                    3
            )
            .joined(
                separator:
                    " "
            )

        let paragraphTwo =
            Array(
                repeating:
                    "SECOND PARAGRAPH WRAPS ACROSS VISUAL LINES.",
                count:
                    3
            )
            .joined(
                separator:
                    " "
            )

        let paragraphThree =
            Array(
                repeating:
                    "THIRD PARAGRAPH WRAPS ACROSS VISUAL LINES.",
                count:
                    3
            )
            .joined(
                separator:
                    " "
            )

        let storage =
            NSTextStorage(
                string:
                    paragraphOne
                    + "\n"
                    + paragraphTwo
                    + "\n"
                    + paragraphThree,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        let container =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            210,
                        height:
                            360
                    )
            )

        manager.ensureLayout(
            for:
                container
        )

        let glyphRange =
            manager.glyphRange(
                for:
                    container
            )

        let string =
            storage.string
                as NSString

        struct Line {
            let fragment:
                NSRect
            let used:
                NSRect
            let glyphs:
                NSRange
            let paragraphStart:
                Int
        }

        func lineFragments()
            -> [Line] {

            var result:
                [Line] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    glyphRange
            ) {
                fragment,
                used,
                textContainer,
                lineGlyphRange,
                _ in

                guard
                    textContainer === container,
                    lineGlyphRange.length > 0
                else {
                    return
                }

                let characters =
                    manager.characterRange(
                        forGlyphRange:
                            lineGlyphRange,
                        actualGlyphRange:
                            nil
                    )

                let location =
                    min(
                        max(
                            0,
                            characters.location
                        ),
                        max(
                            0,
                            storage.length - 1
                        )
                    )

                let paragraph =
                    string.paragraphRange(
                        for:
                            NSRange(
                                location:
                                    location,
                                length:
                                    0
                            )
                    )

                result.append(
                    Line(
                        fragment:
                            fragment,
                        used:
                            used,
                        glyphs:
                            lineGlyphRange,
                        paragraphStart:
                            paragraph.location
                    )
                )
            }

            return result
        }

        let before =
            lineFragments()

        XCTAssertGreaterThan(
            before.count,
            3
        )

        var paragraphOrder:
            [Int] = []

        var seenParagraphs:
            Set<Int> = []

        for line in before {
            if seenParagraphs
                .insert(
                    line.paragraphStart
                )
                .inserted {

                paragraphOrder.append(
                    line.paragraphStart
                )
            }
        }

        XCTAssertEqual(
            paragraphOrder.count,
            3
        )

        let expansion =
            flow.applyVerticalJustification(
                in:
                    container,
                geometry:
                    geometry,
                availableHeight:
                    container
                        .containerSize
                        .height,
                isEligiblePage:
                    true
            )

        XCTAssertGreaterThan(
            expansion,
            0
        )

        let after =
            lineFragments()

        XCTAssertEqual(
            after.count,
            before.count
        )

        let paragraphIndexes =
            Dictionary(
                uniqueKeysWithValues:
                    paragraphOrder
                        .enumerated()
                        .map {
                            (
                                $0.element,
                                $0.offset
                            )
                        }
            )

        for index in after.indices {
            let paragraphIndex =
                paragraphIndexes[
                    before[index]
                        .paragraphStart
                ]!

            let expectedShift =
                expansion
                * CGFloat(
                    paragraphIndex
                )

            XCTAssertEqual(
                after[index]
                    .fragment
                    .minY,
                before[index]
                    .fragment
                    .minY
                    + expectedShift,
                accuracy:
                    0.05
            )

            XCTAssertEqual(
                after[index]
                    .used
                    .minY,
                before[index]
                    .used
                    .minY
                    + expectedShift,
                accuracy:
                    0.05
            )
        }

        // Every visual line within one wrapped paragraph must receive
        // exactly the same vertical shift.
        for paragraphStart
            in paragraphOrder {

            let indices =
                before.indices.filter {
                    before[$0]
                        .paragraphStart
                        == paragraphStart
                }

            XCTAssertGreaterThan(
                indices.count,
                1
            )

            let shifts =
                indices.map {
                    after[$0]
                        .fragment
                        .minY
                    - before[$0]
                        .fragment
                        .minY
                }

            let firstShift =
                shifts.first!

            for shift in shifts {
                XCTAssertEqual(
                    shift,
                    firstShift,
                    accuracy:
                        0.05
                )
            }
        }

        XCTAssertEqual(
            after.first!
                .fragment
                .minY,
            before.first!
                .fragment
                .minY,
            accuracy:
                0.05,
            "The first paragraph stays at the printable top."
        )

        XCTAssertGreaterThan(
            after.last!
                .fragment
                .minY,
            before.last!
                .fragment
                .minY
        )

        // Hit testing must follow the real redistributed TextKit
        // geometry, not a drawing-only translation.
        let probeIndex =
            before.indices.first {
                paragraphIndexes[
                    before[$0]
                        .paragraphStart
                ] == 1
            }!

        let probe =
            after[
                probeIndex
            ]

        var fraction:
            CGFloat = 0

        let glyphAtPoint =
            manager.glyphIndex(
                for:
                    NSPoint(
                        x:
                            probe
                                .used
                                .minX + 1,
                        y:
                            probe
                                .used
                                .midY
                    ),
                in:
                    container,
                fractionOfDistanceThroughGlyph:
                    &fraction
            )

        XCTAssertTrue(
            NSLocationInRange(
                glyphAtPoint,
                probe.glyphs
            ),
            "TextKit hit testing must follow paragraph-redistributed geometry."
        )

        let bounding =
            manager.boundingRect(
                forGlyphRange:
                    glyphRange,
                in:
                    container
            )

        XCTAssertGreaterThanOrEqual(
            bounding.maxY,
            after.last!
                .used
                .maxY
                - 0.5
        )

        // Normal pagination/layout must restore the baseline fragment
        // positions so the paragraph offsets never compound.
        _ =
            try flow.layout(
                container,
                geometry:
                    geometry
            )

        let restored =
            lineFragments()

        XCTAssertEqual(
            restored.count,
            before.count
        )

        for index in restored.indices {
            XCTAssertEqual(
                restored[index]
                    .fragment
                    .minY,
                before[index]
                    .fragment
                    .minY,
                accuracy:
                    0.05
            )

            XCTAssertEqual(
                restored[index]
                    .used
                    .minY,
                before[index]
                    .used
                    .minY,
                accuracy:
                    0.05
            )
        }
    }

    func testWordVerticalJustificationAppliesToFinalDocumentPage()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let storage =
            NSTextStorage(
                string:
                    "FINAL PAGE PARAGRAPH ONE\n"
                    + "FINAL PAGE PARAGRAPH TWO\n"
                    + "FINAL PAGE PARAGRAPH THREE",
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        let container =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            240,
                        height:
                            200
                    )
            )

        let layout =
            try flow.layout(
                container,
                geometry:
                    geometry
            )

        XCTAssertTrue(
            layout.finished,
            "The controlled fixture must be the document's final TextKit page."
        )

        let glyphRange =
            manager.glyphRange(
                for:
                    container
            )

        struct Line {
            let rect:
                NSRect
            let paragraphStart:
                Int
        }

        let string =
            storage.string
                as NSString

        func lines()
            -> [Line] {

            var result:
                [Line] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    glyphRange
            ) {
                rect,
                _,
                textContainer,
                lineGlyphRange,
                _ in

                guard
                    textContainer === container,
                    lineGlyphRange.length > 0
                else {
                    return
                }

                let characters =
                    manager.characterRange(
                        forGlyphRange:
                            lineGlyphRange,
                        actualGlyphRange:
                            nil
                    )

                let location =
                    min(
                        max(
                            0,
                            characters.location
                        ),
                        max(
                            0,
                            storage.length - 1
                        )
                    )

                let paragraph =
                    string.paragraphRange(
                        for:
                            NSRange(
                                location:
                                    location,
                                length:
                                    0
                            )
                    )

                result.append(
                    Line(
                        rect:
                            rect,
                        paragraphStart:
                            paragraph.location
                    )
                )
            }

            return result
        }

        let before =
            lines()

        XCTAssertEqual(
            Set(
                before.map(
                    \.paragraphStart
                )
            )
            .count,
            3
        )

        let expansion =
            flow.applyVerticalJustification(
                in:
                    container,
                geometry:
                    geometry,
                availableHeight:
                    container
                        .containerSize
                        .height,
                isEligiblePage:
                    true
            )

        XCTAssertGreaterThan(
            expansion,
            0,
            "An ordinary final document page remains eligible for Word vertical justification."
        )

        let after =
            lines()

        XCTAssertEqual(
            after.count,
            before.count
        )

        var paragraphOrder:
            [Int] = []

        for line in before {
            if !paragraphOrder
                .contains(
                    line.paragraphStart
                ) {

                paragraphOrder.append(
                    line.paragraphStart
                )
            }
        }

        XCTAssertEqual(
            paragraphOrder.count,
            3
        )

        for (
            paragraphIndex,
            paragraphStart
        ) in paragraphOrder.enumerated() {

            let indices =
                before.indices.filter {
                    before[$0]
                        .paragraphStart
                        == paragraphStart
                }

            let expectedShift =
                expansion
                * CGFloat(
                    paragraphIndex
                )

            for index in indices {
                XCTAssertEqual(
                    after[index]
                        .rect
                        .minY
                    - before[index]
                        .rect
                        .minY,
                    expectedShift,
                    accuracy:
                        0.05
                )
            }
        }

        XCTAssertEqual(
            after.first!
                .rect
                .minY,
            before.first!
                .rect
                .minY,
            accuracy:
                0.05
        )

        XCTAssertGreaterThan(
            after.last!
                .rect
                .minY,
            before.last!
                .rect
                .minY
        )
    }

    func testWordVerticalJustificationStructuralBreakGuard()
        throws
    {
        let storage =
            NSTextStorage(
                string:
                    "FIRST PAGE\u{000C}SECOND PAGE"
            )

        storage.addAttribute(
            .boldWriterPageBreakBefore,
            value:
                true,
            range:
                NSRange(
                    location:
                        11,
                    length:
                        1
                )
        )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        XCTAssertTrue(
            flow.hasStructuralBreak(
                atEndOf:
                    NSRange(
                        location:
                            0,
                        length:
                            11
                    )
            )
        )
    }
}


extension WritingInterfaceTests {
    func testWordVerticalJustificationPreservesWrappedParagraphLeading()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let source =
            Array(
                repeating:
                    "A single paragraph wraps across several visual lines without creating another paragraph.",
                count:
                    7
            )
            .joined(
                separator:
                    " "
            )

        let storage =
            NSTextStorage(
                string:
                    source,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        let container =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            190,
                        height:
                            560
                    )
            )

        manager.ensureLayout(
            for:
                container
        )

        let glyphs =
            manager.glyphRange(
                for:
                    container
            )

        var before:
            [NSRect] = []

        manager.enumerateLineFragments(
            forGlyphRange:
                glyphs
        ) {
            fragment,
            _,
            textContainer,
            lineGlyphs,
            _ in

            if textContainer === container,
               lineGlyphs.length > 0 {

                before.append(
                    fragment
                )
            }
        }

        XCTAssertGreaterThan(
            before.count,
            3
        )

        let expansion =
            flow.applyVerticalJustification(
                in:
                    container,
                geometry:
                    geometry,
                availableHeight:
                    container
                        .containerSize
                        .height,
                isEligiblePage:
                    true
            )

        XCTAssertEqual(
            expansion,
            0,
            accuracy:
                0.001
        )

        var after:
            [NSRect] = []

        manager.enumerateLineFragments(
            forGlyphRange:
                glyphs
        ) {
            fragment,
            _,
            textContainer,
            lineGlyphs,
            _ in

            if textContainer === container,
               lineGlyphs.length > 0 {

                after.append(
                    fragment
                )
            }
        }

        XCTAssertEqual(
            after,
            before
        )
    }

    func testWordVerticalJustificationDistributesOnlyParagraphGaps()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let paragraphOne =
            Array(
                repeating:
                    "Paragraph one wraps naturally over several visual lines.",
                count:
                    4
            )
            .joined(
                separator:
                    " "
            )

        let paragraphTwo =
            Array(
                repeating:
                    "Paragraph two also wraps naturally over several visual lines.",
                count:
                    4
            )
            .joined(
                separator:
                    " "
            )

        let paragraphThree =
            Array(
                repeating:
                    "Paragraph three also wraps naturally over several visual lines.",
                count:
                    4
            )
            .joined(
                separator:
                    " "
            )

        let storage =
            NSTextStorage(
                string:
                    paragraphOne
                    + "\n"
                    + paragraphTwo
                    + "\n"
                    + paragraphThree,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        let container =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            190,
                        height:
                            620
                    )
            )

        manager.ensureLayout(
            for:
                container
        )

        let glyphs =
            manager.glyphRange(
                for:
                    container
            )

        let string =
            storage.string
                as NSString

        struct Line {
            let rect:
                NSRect
            let paragraphStart:
                Int
        }

        func lines()
            -> [Line] {

            var result:
                [Line] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    glyphs
            ) {
                rect,
                _,
                textContainer,
                lineGlyphs,
                _ in

                guard
                    textContainer === container,
                    lineGlyphs.length > 0
                else {
                    return
                }

                let characters =
                    manager.characterRange(
                        forGlyphRange:
                            lineGlyphs,
                        actualGlyphRange:
                            nil
                    )

                let location =
                    min(
                        max(
                            0,
                            characters.location
                        ),
                        max(
                            0,
                            storage.length - 1
                        )
                    )

                let paragraph =
                    string.paragraphRange(
                        for:
                            NSRange(
                                location:
                                    location,
                                length:
                                    0
                            )
                    )

                result.append(
                    Line(
                        rect:
                            rect,
                        paragraphStart:
                            paragraph.location
                    )
                )
            }

            return result
        }

        let before =
            lines()

        var paragraphOrder:
            [Int] = []

        for line in before {
            if !paragraphOrder
                .contains(
                    line.paragraphStart
                ) {

                paragraphOrder.append(
                    line.paragraphStart
                )
            }
        }

        XCTAssertEqual(
            paragraphOrder.count,
            3
        )

        let expansion =
            flow.applyVerticalJustification(
                in:
                    container,
                geometry:
                    geometry,
                availableHeight:
                    container
                        .containerSize
                        .height,
                isEligiblePage:
                    true
            )

        XCTAssertGreaterThan(
            expansion,
            0
        )

        let after =
            lines()

        XCTAssertEqual(
            after.count,
            before.count
        )

        for (
            paragraphIndex,
            paragraphStart
        ) in paragraphOrder.enumerated() {

            let indices =
                before.indices.filter {
                    before[$0]
                        .paragraphStart
                        == paragraphStart
                }

            XCTAssertGreaterThan(
                indices.count,
                1
            )

            let expected =
                expansion
                * CGFloat(
                    paragraphIndex
                )

            for index in indices {
                let shift =
                    after[index]
                        .rect
                        .minY
                    - before[index]
                        .rect
                        .minY

                XCTAssertEqual(
                    shift,
                    expected,
                    accuracy:
                        0.05
                )
            }
        }
    }

    func testWordVerticalJustificationDoesNotShiftLinkedNeighborContainer()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let source =
            (1...80)
            .map {
                "PARAGRAPH \($0) WITH ENOUGH WORDS TO WRAP A LITTLE"
            }
            .joined(
                separator:
                    "\n"
            )

        let storage =
            NSTextStorage(
                string:
                    source,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let manager =
            NSLayoutManager()

        storage.addLayoutManager(
            manager
        )

        let flow =
            PageLayout(
                storage:
                    storage,
                manager:
                    manager
            )

        let first =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            240,
                        height:
                            320
                    )
            )

        let second =
            flow.addContainer(
                size:
                    NSSize(
                        width:
                            240,
                        height:
                            320
                    )
            )

        let firstLayout =
            try flow.layout(
                first,
                geometry:
                    geometry
            )

        let secondLayout =
            try flow.layout(
                second,
                geometry:
                    geometry
            )

        func fragments(
            in container:
                NSTextContainer
        ) -> [NSRect] {
            let glyphs =
                manager.glyphRange(
                    for:
                        container
                )

            var result:
                [NSRect] = []

            manager.enumerateLineFragments(
                forGlyphRange:
                    glyphs
            ) {
                rect,
                _,
                textContainer,
                lineGlyphs,
                _ in

                if textContainer === container,
                   lineGlyphs.length > 0 {

                    result.append(
                        rect
                    )
                }
            }

            return result
        }

        let neighborBefore =
            fragments(
                in:
                    second
            )

        XCTAssertGreaterThan(
            neighborBefore.count,
            1
        )

        let expansion =
            flow.applyVerticalJustification(
                in:
                    first,
                geometry:
                    geometry,
                availableHeight:
                    first
                        .containerSize
                        .height,
                isEligiblePage:
                    true
            )

        XCTAssertGreaterThan(
            expansion,
            0
        )

        let neighborAfter =
            fragments(
                in:
                    second
            )

        XCTAssertEqual(
            neighborAfter.count,
            neighborBefore.count
        )

        for index in neighborBefore.indices {
            XCTAssertEqual(
                neighborAfter[index]
                    .minY,
                neighborBefore[index]
                    .minY,
                accuracy:
                    0.05
            )
        }

        XCTAssertEqual(
            manager.glyphRange(
                for:
                    first
            ),
            firstLayout.glyphs
        )

        XCTAssertEqual(
            manager.glyphRange(
                for:
                    second
            ),
            secondLayout.glyphs
        )

        flow.restoreVerticalJustification(
            in:
                first
        )

        let neighborRestored =
            fragments(
                in:
                    second
            )

        XCTAssertEqual(
            neighborRestored.count,
            neighborBefore.count
        )

        for index in neighborBefore.indices {
            XCTAssertEqual(
                neighborRestored[index]
                    .minY,
                neighborBefore[index]
                    .minY,
                accuracy:
                    0.05
            )
        }
    }
}



// MARK: - Word final-section column balancing foundation

extension WritingInterfaceTests {
    private struct ColumnBalanceProbe {
        let finished: Bool
        let ranges: [NSRange]
        let lineCounts: [Int]
        let usedHeights: [CGFloat]
    }

    private func columnBalanceProbe(
        text: NSAttributedString,
        geometry: PageGeometry,
        height: CGFloat
    ) throws -> ColumnBalanceProbe {
        let flow =
            PageLayout(
                text:
                    text
            )

        var ranges:
            [NSRange] = []

        var lineCounts:
            [Int] = []

        var usedHeights:
            [CGFloat] = []

        var finished =
            false

        for _
            in 0..<geometry.columnCount {

            let container =
                flow.addContainer(
                    size:
                        NSSize(
                            width:
                                geometry.columnWidth,
                            height:
                                height
                        )
                )

            let result =
                try flow.layout(
                    container,
                    geometry:
                        geometry
                )

            ranges.append(
                result.characters
            )

            usedHeights.append(
                flow.manager
                    .usedRect(
                        for:
                            container
                    )
                    .height
            )

            let glyphs =
                flow.manager
                    .glyphRange(
                        for:
                            container
                    )

            var lines =
                0

            flow.manager
                .enumerateLineFragments(
                    forGlyphRange:
                        glyphs
                ) {
                    _,
                    _,
                    textContainer,
                    lineGlyphRange,
                    _ in

                    if textContainer === container,
                       lineGlyphRange.length > 0 {

                        lines +=
                            1
                    }
                }

            lineCounts.append(
                lines
            )

            finished =
                result.finished

            if finished {
                break
            }
        }

        return ColumnBalanceProbe(
            finished:
                finished,
            ranges:
                ranges,
            lineCounts:
                lineCounts,
            usedHeights:
                usedHeights
        )
    }

    private func assertContinuousColumnRanges(
        _ ranges: [NSRange],
        textLength: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            ranges.isEmpty,
            file:
                file,
            line:
                line
        )

        for index
            in 1..<ranges.count {

            XCTAssertEqual(
                NSMaxRange(
                    ranges[
                        index - 1
                    ]
                ),
                ranges[
                    index
                ]
                .location,
                file:
                    file,
                line:
                    line
            )
        }

        XCTAssertEqual(
            NSMaxRange(
                ranges.last!
            ),
            textLength,
            file:
                file,
            line:
                line
        )
    }

    func testWordColumnBalancingPrimitiveBalancesTwoColumns()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let source =
            (1...50)
            .map {
                String(
                    format:
                        "P%03d",
                    $0
                )
            }
            .joined(
                separator:
                    "\n"
            )

        let text =
            NSAttributedString(
                string:
                    source,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let flow =
            PageLayout(
                text:
                    text
            )

        let height =
            try XCTUnwrap(
                flow.minimumBalancedColumnHeight(
                    for:
                        NSRange(
                            location:
                                0,
                            length:
                                text.length
                        ),
                    geometry:
                        geometry
                )
            )

        XCTAssertLessThan(
            height,
            geometry
                .contentSize
                .height
        )

        let balanced =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    height
            )

        XCTAssertTrue(
            balanced.finished
        )

        XCTAssertEqual(
            balanced.ranges.count,
            2
        )

        XCTAssertEqual(
            balanced.lineCounts.reduce(
                0,
                +
            ),
            50
        )

        XCTAssertLessThanOrEqual(
            (
                balanced.lineCounts.max()
                    ?? 0
            )
            - (
                balanced.lineCounts.min()
                    ?? 0
            ),
            1
        )

        assertContinuousColumnRanges(
            balanced.ranges,
            textLength:
                text.length
        )

        let smaller =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    max(
                        1,
                        height - 1
                    )
            )

        XCTAssertFalse(
            smaller.finished
        )

        print(
            "COLUMN_BALANCE_STAGE2A_2 "
            + "height=\(height) "
            + "lines=\(balanced.lineCounts) "
            + "used=\(balanced.usedHeights)"
        )
    }

    func testWordColumnBalancingPrimitiveBalancesThreeColumns()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            3

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let source =
            (1...50)
            .map {
                String(
                    format:
                        "P%03d",
                    $0
                )
            }
            .joined(
                separator:
                    "\n"
            )

        let text =
            NSAttributedString(
                string:
                    source,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let flow =
            PageLayout(
                text:
                    text
            )

        let height =
            try XCTUnwrap(
                flow.minimumBalancedColumnHeight(
                    for:
                        NSRange(
                            location:
                                0,
                            length:
                                text.length
                        ),
                    geometry:
                        geometry
                )
            )

        let balanced =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    height
            )

        XCTAssertTrue(
            balanced.finished
        )

        XCTAssertEqual(
            balanced.ranges.count,
            3
        )

        XCTAssertEqual(
            balanced.lineCounts.reduce(
                0,
                +
            ),
            50
        )

        XCTAssertLessThanOrEqual(
            (
                balanced.lineCounts.max()
                    ?? 0
            )
            - (
                balanced.lineCounts.min()
                    ?? 0
            ),
            1
        )

        assertContinuousColumnRanges(
            balanced.ranges,
            textLength:
                text.length
        )

        let smaller =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    max(
                        1,
                        height - 1
                    )
            )

        XCTAssertFalse(
            smaller.finished
        )

        print(
            "COLUMN_BALANCE_STAGE2A_3 "
            + "height=\(height) "
            + "lines=\(balanced.lineCounts) "
            + "used=\(balanced.usedHeights)"
        )
    }

    func testWordColumnBalancingPrimitivePreservesWrappedParagraphFlow()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let source =
            (1...8)
            .map {
                index in

                Array(
                    repeating:
                        "Wrapped paragraph \(index) contains enough text to occupy multiple visual lines.",
                    count:
                        index.isMultiple(
                            of:
                                3
                        )
                            ? 3
                            : 2
                )
                .joined(
                    separator:
                        " "
                )
            }
            .joined(
                separator:
                    "\n"
            )

        let text =
            NSAttributedString(
                string:
                    source,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            )

        let flow =
            PageLayout(
                text:
                    text
            )

        let height =
            try XCTUnwrap(
                flow.minimumBalancedColumnHeight(
                    for:
                        NSRange(
                            location:
                                0,
                            length:
                                text.length
                        ),
                    geometry:
                        geometry
                )
            )

        let balanced =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    height
            )

        XCTAssertTrue(
            balanced.finished
        )

        XCTAssertEqual(
            balanced.ranges.count,
            2
        )

        assertContinuousColumnRanges(
            balanced.ranges,
            textLength:
                text.length
        )

        let smaller =
            try columnBalanceProbe(
                text:
                    text,
                geometry:
                    geometry,
                height:
                    max(
                        1,
                        height - 1
                    )
            )

        XCTAssertFalse(
            smaller.finished
        )

        print(
            "COLUMN_BALANCE_STAGE2A_WRAPPED "
            + "height=\(height) "
            + "ranges=\(balanced.ranges) "
            + "used=\(balanced.usedHeights)"
        )
    }

    func testWordColumnBalancingPrimitiveHonorsNoColumnBalance()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.noColumnBalance =
            true

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            NSAttributedString(
                string:
                    (1...40)
                    .map {
                        "Paragraph \($0)"
                    }
                    .joined(
                        separator:
                            "\n"
                    )
            )

        let flow =
            PageLayout(
                text:
                    text
            )

        XCTAssertNil(
            try flow.minimumBalancedColumnHeight(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            text.length
                    ),
                geometry:
                    geometry
            )
        )
    }

    func testWordColumnBalancingPrimitiveSkipsSingleColumnAndOversizedRange()
        throws
    {
        var singleColumnSettings =
            PageSettings()

        singleColumnSettings.columnCount =
            1

        let singleGeometry =
            try PageGeometry(
                singleColumnSettings
            )

        let text =
            NSAttributedString(
                string:
                    "One\nTwo\nThree"
            )

        let singleFlow =
            PageLayout(
                text:
                    text
            )

        XCTAssertNil(
            try singleFlow.minimumBalancedColumnHeight(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            text.length
                    ),
                geometry:
                    singleGeometry
            )
        )

        var multiSettings =
            PageSettings()

        multiSettings.columnCount =
            2

        let multiGeometry =
            try PageGeometry(
                multiSettings
            )

        XCTAssertNil(
            try singleFlow.minimumBalancedColumnHeight(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            text.length + 1
                    ),
                geometry:
                    multiGeometry
            )
        )
    }
}



// MARK: - Word final-section column balancing — real screen pagination

extension WritingInterfaceTests {
    private func screenColumnLineCounts(
        _ editor: PaginatedEditor,
        physicalPage: Int
    ) -> [Int] {
        guard
            editor.pageContainerIndices
                .indices
                .contains(
                    physicalPage
                )
        else {
            return []
        }

        return editor
            .pageContainerIndices[
                physicalPage
            ]
            .compactMap {
                containerIndex -> Int? in

                guard
                    containerIndex >= 0,
                    containerIndex
                        < editor.flow
                            .manager
                            .textContainers
                            .count
                else {
                    return nil
                }

                let container =
                    editor.flow
                        .manager
                        .textContainers[
                            containerIndex
                        ]

                let glyphs =
                    editor.flow
                        .manager
                        .glyphRange(
                            for:
                                container
                        )

                var count =
                    0

                editor.flow
                    .manager
                    .enumerateLineFragments(
                        forGlyphRange:
                            glyphs
                    ) {
                        _,
                        _,
                        textContainer,
                        lineGlyphRange,
                        _ in

                        if textContainer === container,
                           lineGlyphRange.length > 0 {
                            count += 1
                        }
                    }

                return count
            }
    }

    private func screenColumnHeights(
        _ editor: PaginatedEditor,
        physicalPage: Int
    ) -> [CGFloat] {
        guard
            editor.pageContainerIndices
                .indices
                .contains(
                    physicalPage
                )
        else {
            return []
        }

        return editor
            .pageContainerIndices[
                physicalPage
            ]
            .compactMap {
                containerIndex -> CGFloat? in

                guard
                    containerIndex >= 0,
                    containerIndex
                        < editor.flow
                            .manager
                            .textContainers
                            .count
                else {
                    return nil
                }

                return editor.flow
                    .manager
                    .textContainers[
                        containerIndex
                    ]
                    .containerSize
                    .height
            }
    }

    private func screenBalanceText(
        paragraphCount: Int
    ) -> NSAttributedString {
        NSAttributedString(
            string:
                (1...paragraphCount)
                .map {
                    String(
                        format:
                            "P%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                ),
            attributes:
                [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                14
                        )
                ]
        )
    }

    func testPaginatedEditorBalancesFinalTwoColumnPage()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            screenBalanceText(
                paragraphCount:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        let heights =
            screenColumnHeights(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            heights.count,
            2
        )

        XCTAssertLessThan(
            heights.max()
                ?? geometry.contentSize.height,
            geometry.contentSize.height - 1
        )

        XCTAssertLessThanOrEqual(
            abs(
                (heights.max() ?? 0)
                - (heights.min() ?? 0)
            ),
            0.1
        )

        let lines =
            screenColumnLineCounts(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            lines.reduce(
                0,
                +
            ),
            50
        )

        XCTAssertLessThanOrEqual(
            (lines.max() ?? 0)
                - (lines.min() ?? 0),
            1
        )

        XCTAssertEqual(
            editor.pageRanges[
                0
            ],
            NSRange(
                location:
                    0,
                length:
                    text.length
            )
        )

        print(
            "COLUMN_BALANCE_SCREEN_2 "
            + "heights=\(heights) "
            + "lines=\(lines) "
            + "range=\(editor.pageRanges[0])"
        )
    }

    func testPaginatedEditorBalancesFinalThreeColumnPage()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            3

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            screenBalanceText(
                paragraphCount:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        let heights =
            screenColumnHeights(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            heights.count,
            3
        )

        XCTAssertLessThan(
            heights.max()
                ?? geometry.contentSize.height,
            geometry.contentSize.height - 1
        )

        XCTAssertLessThanOrEqual(
            abs(
                (heights.max() ?? 0)
                - (heights.min() ?? 0)
            ),
            0.1
        )

        let lines =
            screenColumnLineCounts(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            lines.reduce(
                0,
                +
            ),
            50
        )

        XCTAssertLessThanOrEqual(
            (lines.max() ?? 0)
                - (lines.min() ?? 0),
            1
        )

        print(
            "COLUMN_BALANCE_SCREEN_3 "
            + "heights=\(heights) "
            + "lines=\(lines)"
        )
    }

    func testPaginatedEditorKeepsIntermediateMultiColumnPagesFullHeight()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            screenBalanceText(
                paragraphCount:
                    100
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertGreaterThanOrEqual(
            editor.pages.count,
            2
        )

        let firstHeights =
            screenColumnHeights(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            firstHeights.count,
            2
        )

        for height
            in firstHeights {

            XCTAssertEqual(
                height,
                geometry
                    .contentSize
                    .height,
                accuracy:
                    0.5
            )
        }

        let finalPage =
            editor.pages.count - 1

        let finalHeights =
            screenColumnHeights(
                editor,
                physicalPage:
                    finalPage
            )

        XCTAssertEqual(
            finalHeights.count,
            2
        )

        XCTAssertLessThan(
            finalHeights.max()
                ?? geometry.contentSize.height,
            geometry.contentSize.height - 1
        )

        let finalLines =
            screenColumnLineCounts(
                editor,
                physicalPage:
                    finalPage
            )

        XCTAssertLessThanOrEqual(
            (finalLines.max() ?? 0)
                - (finalLines.min() ?? 0),
            1
        )

        print(
            "COLUMN_BALANCE_SCREEN_FINAL_ONLY "
            + "pages=\(editor.pages.count) "
            + "firstHeights=\(firstHeights) "
            + "finalHeights=\(finalHeights) "
            + "finalLines=\(finalLines)"
        )
    }

    func testPaginatedEditorHonorsNoColumnBalanceWithSequentialFinalColumns()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        settings.noColumnBalance =
            true

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            screenBalanceText(
                paragraphCount:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        let heights =
            screenColumnHeights(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            heights.count,
            2
        )

        for height
            in heights {

            XCTAssertEqual(
                height,
                geometry
                    .contentSize
                    .height,
                accuracy:
                    0.5
            )
        }

        let lines =
            screenColumnLineCounts(
                editor,
                physicalPage:
                    0
            )

        XCTAssertEqual(
            lines.reduce(
                0,
                +
            ),
            50
        )

        XCTAssertGreaterThan(
            (lines.max() ?? 0)
                - (lines.min() ?? 0),
            1
        )

        print(
            "COLUMN_BALANCE_SCREEN_DISABLED "
            + "heights=\(heights) "
            + "lines=\(lines)"
        )
    }
}



// MARK: - Word multi-column vertical justification

extension WritingInterfaceTests {
    private struct WordMultiColumnVAlignSnapshot:
        Equatable
    {
        let size: NSSize
        let glyphs: NSRange
        let characters: NSRange
        let fragmentRects: [NSRect]
        let usedRects: [NSRect]

        var bottom: CGFloat {
            usedRects.map(\.maxY).max() ?? 0
        }
    }

    private func wordMultiColumnVAlignSnapshot(
        flow: PageLayout,
        container: NSTextContainer
    ) -> WordMultiColumnVAlignSnapshot {
        let glyphs =
            flow.manager.glyphRange(
                for:
                    container
            )

        let characters =
            flow.manager.characterRange(
                forGlyphRange:
                    glyphs,
                actualGlyphRange:
                    nil
            )

        var fragmentRects: [NSRect] = []
        var usedRects: [NSRect] = []

        flow.manager.enumerateLineFragments(
            forGlyphRange:
                glyphs
        ) {
            fragmentRect,
            usedRect,
            textContainer,
            lineGlyphRange,
            _ in

            if textContainer === container,
               lineGlyphRange.length > 0 {

                fragmentRects.append(
                    fragmentRect
                )

                usedRects.append(
                    usedRect
                )
            }
        }

        return WordMultiColumnVAlignSnapshot(
            size:
                container.containerSize,
            glyphs:
                glyphs,
            characters:
                characters,
            fragmentRects:
                fragmentRects,
            usedRects:
                usedRects
        )
    }

    private func wordMultiColumnVAlignText(
        paragraphs: Int
    ) -> NSAttributedString {
        NSAttributedString(
            string:
                (1...paragraphs)
                .map {
                    String(
                        format:
                            "P%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                ),
            attributes:
                [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                14
                        )
                ]
        )
    }

    func testWordMultiColumnVerticalJustificationResidualTolerancePreservesNeighbors()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            3

        settings.columnSpacing =
            24

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordMultiColumnVAlignText(
                paragraphs:
                    50
            )

        let flow =
            PageLayout(
                text:
                    text
            )

        let height =
            try XCTUnwrap(
                flow.minimumBalancedColumnHeight(
                    for:
                        NSRange(
                            location:
                                0,
                            length:
                                text.length
                        ),
                    geometry:
                        geometry
                )
            )

        let containers =
            (0..<3)
                .map {
                    _ in

                    flow.addContainer(
                        size:
                            NSSize(
                                width:
                                    geometry.columnWidth,
                                height:
                                    height
                            )
                    )
                }

        for container in containers {
            _ =
                try flow.layout(
                    container,
                    geometry:
                        geometry
                )
        }

        let baseline =
            containers.map {
                wordMultiColumnVAlignSnapshot(
                    flow:
                        flow,
                    container:
                        $0
                )
            }

        let residuals =
            baseline.map {
                height - $0.bottom
            }

        XCTAssertLessThanOrEqual(
            residuals[0],
            0.5
        )

        XCTAssertLessThanOrEqual(
            residuals[1],
            0.5
        )

        XCTAssertGreaterThan(
            residuals[2],
            0.5
        )

        var expansions: [CGFloat] = []

        for index in containers.indices {
            let before =
                containers.map {
                    wordMultiColumnVAlignSnapshot(
                        flow:
                            flow,
                        container:
                            $0
                    )
                }

            let expansion =
                flow.applyVerticalJustification(
                    in:
                        containers[index],
                    geometry:
                        geometry,
                    availableHeight:
                        containers[index]
                            .containerSize
                            .height,
                    isEligiblePage:
                        true
                )

            expansions.append(
                expansion
            )

            let after =
                containers.map {
                    wordMultiColumnVAlignSnapshot(
                        flow:
                            flow,
                        container:
                            $0
                    )
                }

            for other in containers.indices
                where other != index {

                XCTAssertEqual(
                    after[other],
                    before[other],
                    "Justifying one balanced Word column must not disturb a neighboring TextKit column."
                )
            }

            for column in containers.indices {
                XCTAssertEqual(
                    after[column].size,
                    baseline[column].size
                )

                XCTAssertEqual(
                    after[column].glyphs,
                    baseline[column].glyphs
                )

                XCTAssertEqual(
                    after[column].characters,
                    baseline[column].characters
                )
            }
        }

        XCTAssertEqual(
            expansions[0],
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            expansions[1],
            0,
            accuracy:
                0.000001
        )

        XCTAssertGreaterThan(
            expansions[2],
            0.5
        )

        let justified =
            containers.map {
                wordMultiColumnVAlignSnapshot(
                    flow:
                        flow,
                    container:
                        $0
                )
            }

        XCTAssertEqual(
            justified[0],
            baseline[0]
        )

        XCTAssertEqual(
            justified[1],
            baseline[1]
        )

        XCTAssertGreaterThan(
            justified[2].bottom,
            baseline[2].bottom + 1
        )

        XCTAssertEqual(
            justified[2].bottom,
            height,
            accuracy:
                0.1
        )

        for index in containers.indices.reversed() {
            let before =
                containers.map {
                    wordMultiColumnVAlignSnapshot(
                        flow:
                            flow,
                        container:
                            $0
                    )
                }

            flow.restoreVerticalJustification(
                in:
                    containers[index]
            )

            let after =
                containers.map {
                    wordMultiColumnVAlignSnapshot(
                        flow:
                            flow,
                        container:
                            $0
                    )
                }

            for other in containers.indices
                where other != index {

                XCTAssertEqual(
                    after[other],
                    before[other],
                    "Restoring one Word column must not disturb a neighboring column."
                )
            }
        }

        XCTAssertEqual(
            containers.map {
                wordMultiColumnVAlignSnapshot(
                    flow:
                        flow,
                    container:
                        $0
                )
            },
            baseline
        )

        print(
            "WORD_VALIGN_MULTICOL_DIRECT "
            + "height=\(height) "
            + "residuals=\(residuals) "
            + "expansions=\(expansions) "
            + "baselineBottoms=\(baseline.map { $0.bottom }) "
            + "justifiedBottoms=\(justified.map { $0.bottom })"
        )
    }

    func testPaginatedEditorAppliesVerticalBothToBalancedThreeColumnFinalPage()
        throws
    {
        var bothSettings =
            PageSettings()

        bothSettings.columnCount =
            3

        bothSettings.columnSpacing =
            24

        bothSettings.verticalPageAlignment =
            .both

        var topSettings =
            bothSettings

        topSettings.verticalPageAlignment =
            nil

        let text =
            wordMultiColumnVAlignText(
                paragraphs:
                    50
            )

        let bothEditor =
            PaginatedEditor(
                text:
                    text
            )

        bothEditor.configure(
            printLayout:
                true,
            settings:
                bothSettings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        bothEditor.finishPagination()

        XCTAssertNil(
            bothEditor.lastLayoutError
        )

        let topEditor =
            PaginatedEditor(
                text:
                    text
            )

        topEditor.configure(
            printLayout:
                true,
            settings:
                topSettings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        topEditor.finishPagination()

        XCTAssertNil(
            topEditor.lastLayoutError
        )

        XCTAssertEqual(
            bothEditor.pageRanges,
            topEditor.pageRanges
        )

        let both =
            bothEditor.pageContainerIndices[0]
                .map {
                    index in

                    wordMultiColumnVAlignSnapshot(
                        flow:
                            bothEditor.flow,
                        container:
                            bothEditor.flow
                                .manager
                                .textContainers[index]
                    )
                }

        let top =
            topEditor.pageContainerIndices[0]
                .map {
                    index in

                    wordMultiColumnVAlignSnapshot(
                        flow:
                            topEditor.flow,
                        container:
                            topEditor.flow
                                .manager
                                .textContainers[index]
                    )
                }

        XCTAssertEqual(
            both.count,
            3
        )

        XCTAssertEqual(
            top.count,
            3
        )

        for index in 0..<3 {
            XCTAssertEqual(
                both[index].size,
                top[index].size
            )

            XCTAssertEqual(
                both[index].glyphs,
                top[index].glyphs
            )

            XCTAssertEqual(
                both[index].characters,
                top[index].characters
            )
        }

        XCTAssertEqual(
            both[0],
            top[0]
        )

        XCTAssertEqual(
            both[1],
            top[1]
        )

        XCTAssertGreaterThan(
            both[2].bottom,
            top[2].bottom + 1
        )

        XCTAssertEqual(
            both[2].bottom,
            both[2].size.height,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            both[0].characters.location,
            0
        )

        XCTAssertEqual(
            NSMaxRange(
                both[0].characters
            ),
            both[1].characters.location
        )

        XCTAssertEqual(
            NSMaxRange(
                both[1].characters
            ),
            both[2].characters.location
        )

        XCTAssertEqual(
            NSMaxRange(
                both[2].characters
            ),
            text.length
        )

        print(
            "WORD_VALIGN_MULTICOL_SCREEN "
            + "ranges=\(both.map { $0.characters }) "
            + "heights=\(both.map { $0.size.height }) "
            + "bothBottoms=\(both.map { $0.bottom }) "
            + "topBottoms=\(top.map { $0.bottom })"
        )
    }

    func testPaginatedEditorNoColumnBalanceVerticalBothStaysSequentialAndFullHeight()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        settings.noColumnBalance =
            true

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordMultiColumnVAlignText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertEqual(
            editor.pages.count,
            1
        )

        let snapshots =
            editor.pageContainerIndices[0]
                .map {
                    index in

                    wordMultiColumnVAlignSnapshot(
                        flow:
                            editor.flow,
                        container:
                            editor.flow
                                .manager
                                .textContainers[index]
                    )
                }

        XCTAssertEqual(
            snapshots.count,
            2
        )

        for snapshot in snapshots {
            XCTAssertEqual(
                snapshot.size.height,
                geometry.contentSize.height,
                accuracy:
                    0.5
            )
        }

        XCTAssertEqual(
            snapshots[0].characters.location,
            0
        )

        XCTAssertEqual(
            NSMaxRange(
                snapshots[0].characters
            ),
            snapshots[1].characters.location
        )

        XCTAssertEqual(
            NSMaxRange(
                snapshots[1].characters
            ),
            text.length
        )

        XCTAssertGreaterThan(
            snapshots[0].characters.length,
            snapshots[1].characters.length
        )

        XCTAssertEqual(
            snapshots[0].bottom,
            geometry.contentSize.height,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            snapshots[1].bottom,
            geometry.contentSize.height,
            accuracy:
                0.1
        )

        print(
            "WORD_VALIGN_MULTICOL_NCB "
            + "ranges=\(snapshots.map { $0.characters }) "
            + "heights=\(snapshots.map { $0.size.height }) "
            + "bottoms=\(snapshots.map { $0.bottom })"
        )
    }
}



// MARK: - Continuous / nextColumn final-section balancing

extension WritingInterfaceTests {
    private func sectionFinalBalanceText(
        firstParagraphs: Int,
        secondParagraphs: Int
    ) -> (
        text: NSAttributedString,
        boundary: Int
    ) {
        let first =
            (1...firstParagraphs)
                .map {
                    String(
                        format:
                            "A%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                )
                + "\n"

        let second =
            (1...secondParagraphs)
                .map {
                    String(
                        format:
                            "B%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                )

        return (
            NSAttributedString(
                string:
                    first + second,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            ),
            (
                first
                    as NSString
            )
            .length
        )
    }

    private func sectionFinalBalanceEditor(
        breakType: DocumentSection.BreakType,
        firstParagraphs: Int,
        secondParagraphs: Int,
        noColumnBalance: Bool = false
    ) throws -> (
        editor: PaginatedEditor,
        boundary: Int,
        fullHeight: CGFloat,
        textLength: Int
    ) {
        var first =
            PageSettings()

        first.columnCount =
            2

        first.columnSpacing =
            24

        var second =
            first

        if noColumnBalance {
            second.noColumnBalance =
                true
        }

        let source =
            sectionFinalBalanceText(
                firstParagraphs:
                    firstParagraphs,
                secondParagraphs:
                    secondParagraphs
            )

        let sections =
            [
                DocumentSection(
                    location:
                        0,
                    page:
                        first
                ),

                DocumentSection(
                    location:
                        source.boundary,
                    page:
                        second,
                    breakType:
                        breakType
                )
            ]

        let editor =
            PaginatedEditor(
                text:
                    source.text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        return (
            editor:
                editor,
            boundary:
                source.boundary,
            fullHeight:
                try PageGeometry(
                    first
                )
                .contentSize
                .height,
            textLength:
                source.text.length
        )
    }

    private func sectionFinalBalanceActiveHeights(
        _ editor: PaginatedEditor
    ) -> [[CGFloat]] {
        zip(
            editor.pageContainerIndices,
            editor.pageRanges
        )
        .map {
            indices,
            pageRange in

            let pageEnd =
                NSMaxRange(
                    pageRange
                )

            return indices.compactMap {
                index -> CGFloat? in

                guard
                    index >= 0,
                    index
                        < editor.flow
                            .manager
                            .textContainers
                            .count
                else {
                    return nil
                }

                let container =
                    editor.flow
                        .manager
                        .textContainers[
                            index
                        ]

                let glyphs =
                    editor.flow
                        .manager
                        .glyphRange(
                            for:
                                container
                        )

                let characters =
                    editor.flow
                        .manager
                        .characterRange(
                            forGlyphRange:
                                glyphs,
                            actualGlyphRange:
                                nil
                        )

                if characters.length == 0,
                   characters.location >= pageEnd {
                    return nil
                }

                return container
                    .containerSize
                    .height
            }
        }
    }

    func testContinuousMixedTerminalPageRemainsUnbalanced()
        throws
    {
        let result =
            try sectionFinalBalanceEditor(
                breakType:
                    .continuous,
                firstParagraphs:
                    20,
                secondParagraphs:
                    30
            )

        XCTAssertEqual(
            result.editor.pageRanges.count,
            1
        )

        let range =
            result.editor.pageRanges[0]

        XCTAssertLessThan(
            range.location,
            result.boundary
        )

        XCTAssertGreaterThan(
            NSMaxRange(
                range
            ),
            result.boundary
        )

        let heights =
            sectionFinalBalanceActiveHeights(
                result.editor
            )[0]

        XCTAssertEqual(
            heights.count,
            2
        )

        for height in heights {
            XCTAssertEqual(
                height,
                result.fullHeight,
                accuracy:
                    0.5
            )
        }

        print(
            "SECTION_BALANCE_CONTINUOUS_MIXED "
            + "range=\(range) "
            + "boundary=\(result.boundary) "
            + "heights=\(heights)"
        )
    }

    func testNextColumnMixedTerminalPageRemainsUnbalanced()
        throws
    {
        let result =
            try sectionFinalBalanceEditor(
                breakType:
                    .nextColumn,
                firstParagraphs:
                    8,
                secondParagraphs:
                    20
            )

        XCTAssertEqual(
            result.editor.pageRanges.count,
            1
        )

        let range =
            result.editor.pageRanges[0]

        XCTAssertLessThan(
            range.location,
            result.boundary
        )

        XCTAssertGreaterThan(
            NSMaxRange(
                range
            ),
            result.boundary
        )

        let heights =
            sectionFinalBalanceActiveHeights(
                result.editor
            )[0]

        XCTAssertEqual(
            heights.count,
            2
        )

        for height in heights {
            XCTAssertEqual(
                height,
                result.fullHeight,
                accuracy:
                    0.5
            )
        }

        print(
            "SECTION_BALANCE_NEXTCOLUMN_MIXED "
            + "range=\(range) "
            + "boundary=\(result.boundary) "
            + "heights=\(heights)"
        )
    }

    func testContinuousFinalSectionBalancesOnPureFinalPage()
        throws
    {
        let result =
            try sectionFinalBalanceEditor(
                breakType:
                    .continuous,
                firstParagraphs:
                    8,
                secondParagraphs:
                    92
            )

        XCTAssertEqual(
            result.editor.pageRanges.count,
            2
        )

        let finalRange =
            result.editor.pageRanges[1]

        XCTAssertGreaterThanOrEqual(
            finalRange.location,
            result.boundary
        )

        XCTAssertEqual(
            NSMaxRange(
                finalRange
            ),
            result.textLength
        )

        let heights =
            sectionFinalBalanceActiveHeights(
                result.editor
            )

        for height in heights[0] {
            XCTAssertEqual(
                height,
                result.fullHeight,
                accuracy:
                    0.5
            )
        }

        XCTAssertEqual(
            heights[1].count,
            2
        )

        XCTAssertLessThan(
            heights[1].max()
                ?? result.fullHeight,
            result.fullHeight - 1
        )

        XCTAssertLessThanOrEqual(
            abs(
                (
                    heights[1].max()
                        ?? 0
                )
                - (
                    heights[1].min()
                        ?? 0
                )
            ),
            0.1
        )

        print(
            "SECTION_BALANCE_CONTINUOUS_FINAL "
            + "ranges=\(result.editor.pageRanges) "
            + "heights=\(heights)"
        )
    }

    func testNextColumnFinalSectionBalancesOnPureFinalPage()
        throws
    {
        let result =
            try sectionFinalBalanceEditor(
                breakType:
                    .nextColumn,
                firstParagraphs:
                    8,
                secondParagraphs:
                    92
            )

        XCTAssertEqual(
            result.editor.pageRanges.count,
            2
        )

        let finalRange =
            result.editor.pageRanges[1]

        XCTAssertGreaterThanOrEqual(
            finalRange.location,
            result.boundary
        )

        XCTAssertEqual(
            NSMaxRange(
                finalRange
            ),
            result.textLength
        )

        let heights =
            sectionFinalBalanceActiveHeights(
                result.editor
            )

        for height in heights[0] {
            XCTAssertEqual(
                height,
                result.fullHeight,
                accuracy:
                    0.5
            )
        }

        XCTAssertEqual(
            heights[1].count,
            2
        )

        XCTAssertLessThan(
            heights[1].max()
                ?? result.fullHeight,
            result.fullHeight - 1
        )

        XCTAssertLessThanOrEqual(
            abs(
                (
                    heights[1].max()
                        ?? 0
                )
                - (
                    heights[1].min()
                        ?? 0
                )
            ),
            0.1
        )

        print(
            "SECTION_BALANCE_NEXTCOLUMN_FINAL "
            + "ranges=\(result.editor.pageRanges) "
            + "heights=\(heights)"
        )
    }

    func testContinuousAndNextColumnFinalSectionsHonorNoColumnBalance()
        throws
    {
        for breakType
            in [
                DocumentSection.BreakType.continuous,
                DocumentSection.BreakType.nextColumn
            ] {

            let result =
                try sectionFinalBalanceEditor(
                    breakType:
                        breakType,
                    firstParagraphs:
                        8,
                    secondParagraphs:
                        92,
                    noColumnBalance:
                        true
                )

            XCTAssertEqual(
                result.editor.pageRanges.count,
                2
            )

            let heights =
                sectionFinalBalanceActiveHeights(
                    result.editor
                )

            for pageHeights in heights {
                for height in pageHeights {
                    XCTAssertEqual(
                        height,
                        result.fullHeight,
                        accuracy:
                            0.5
                    )
                }
            }

            print(
                "SECTION_BALANCE_NCB "
                + "break=\(breakType.rawValue) "
                + "ranges=\(result.editor.pageRanges) "
                + "heights=\(heights)"
            )
        }
    }
}
