import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class ListEditingTests: XCTestCase {
    private func editor(_ value: String) -> (NSTextView, EditorController) {
        let view = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 500)
        )

        view.textStorage?.setAttributedString(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.textColor
                ]
            )
        )

        let controller = EditorController()
        controller.attach(view)

        return (view, controller)
    }

    func testBulletListUsesNativeTextListAndTogglesOff() throws {
        let (view, controller) = editor("Alpha\nBeta\nGamma\n")
        view.setSelectedRange(
            NSRange(location: 0, length: view.string.utf16.count)
        )

        controller.toggleBulletList()

        let first = try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        let nativeList = try XCTUnwrap(first.textLists.last)
        XCTAssertFalse(nativeList.isOrdered)

        let betaLocation = (view.string as NSString).range(of: "Beta").location
        let second = try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: betaLocation,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        XCTAssertFalse(try XCTUnwrap(second.textLists.last).isOrdered)
        XCTAssertTrue(
            ObjectIdentifier(nativeList)
                == ObjectIdentifier(try XCTUnwrap(second.textLists.last))
        )

        controller.toggleBulletList()

        let removed = try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        XCTAssertTrue(removed.textLists.isEmpty)
    }

    func testNumberedListUsesNativeOrderedTextList() throws {
        let (view, controller) = editor("One\nTwo\nThree\n")
        view.setSelectedRange(
            NSRange(location: 0, length: view.string.utf16.count)
        )

        controller.toggleNumberedList()

        let style = try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        let list = try XCTUnwrap(style.textLists.last)

        XCTAssertTrue(list.isOrdered)
        XCTAssertEqual(list.startingItemNumber, 1)
    }

    func testSwitchingBulletListToNumberedListChangesNativeListKind() throws {
        let (view, controller) = editor("First\nSecond\n")
        view.setSelectedRange(
            NSRange(location: 0, length: view.string.utf16.count)
        )

        controller.toggleBulletList()
        controller.toggleNumberedList()

        let style = try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        XCTAssertTrue(try XCTUnwrap(style.textLists.last).isOrdered)
    }

    func testNativeListsExportAndImportThroughDOCX() throws {
        let paragraph = NSMutableParagraphStyle()
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 4
        paragraph.textLists = [list]

        let original = NSAttributedString(
            string: "Fourth item\nFifth item\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraph
            ]
        )

        let data = try DOCXExporter.data(
            from: original,
            title: "List Round Trip"
        )

        let imported = try DOCXImporter.text(from: data)

        XCTAssertTrue(imported.string.contains("Fourth item"))
        XCTAssertTrue(imported.string.contains("Fifth item"))

        let importedStyle = try XCTUnwrap(
            imported.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )

        let importedList = try XCTUnwrap(importedStyle.textLists.last)
        XCTAssertTrue(importedList.isOrdered)
        XCTAssertEqual(importedList.startingItemNumber, 4)
    }

    func testChecklistUsesStructuredMetadataAndCheckedState() throws {
        let (view, controller) =
            editor(
                "Buy paper\nEdit chapter\n"
            )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        controller.toggleChecklist()

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            false
        )

        XCTAssertEqual(
            controller.formatting.checklist,
            .on
        )

        XCTAssertEqual(
            controller.formatting.bulletList,
            .off
        )

        controller.toggleChecklistItem()

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        let style =
            try XCTUnwrap(
                view.textStorage?
                    .attribute(
                        .paragraphStyle,
                        at:
                            0,
                        effectiveRange:
                            nil
                    )
                    as? NSParagraphStyle
            )

        XCTAssertEqual(
            style.textLists.last?
                .markerFormat,
            .check
        )
    }

    func testChecklistSurvivesNativeSaveAndReopen() throws {
        let (view, controller) =
            editor(
                "Persist checklist\n"
            )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        controller.toggleChecklist()
        controller.toggleChecklistItem()

        let source =
            NSAttributedString(
                attributedString:
                    try XCTUnwrap(
                        view.textStorage
                    )
            )

        let wrapper =
            try BOLDWriterDocument
                .packageWrapper(
                    text:
                        source,
                    metadata:
                        DocumentMetadata()
                )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .boldWriterDocument
            )

        XCTAssertEqual(
            reopened.text
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        XCTAssertEqual(
            reopened.text
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        let style =
            try XCTUnwrap(
                reopened.text
                    .attribute(
                        .paragraphStyle,
                        at:
                            0,
                        effectiveRange:
                            nil
                    )
                    as? NSParagraphStyle
            )

        XCTAssertEqual(
            style.textLists.last?
                .markerFormat,
            .check
        )
    }

    func testChecklistSurvivesBOLDAuthoredDOCXRoundTrip() throws {
        let (view, controller) =
            editor(
                "Unchecked item\nChecked item\n"
            )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        controller.toggleChecklist()

        let checkedLocation =
            (view.string as NSString)
                .range(
                    of:
                        "Checked item"
                )
                .location

        XCTAssertNotEqual(
            checkedLocation,
            NSNotFound
        )

        view.setSelectedRange(
            NSRange(
                location:
                    checkedLocation,
                length:
                    0
            )
        )

        controller.toggleChecklistItem()

        let source =
            NSAttributedString(
                attributedString:
                    try XCTUnwrap(
                        view.textStorage
                    )
            )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Checklist Round Trip"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        XCTAssertNotNil(
            entries.first {
                $0.path
                    == "word/boldwriter-checklists.xml"
            }
        )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterChecklist,
                at:
                    0,
                effectiveRange:
                    nil
            )
                as? Bool,
            true
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterChecklistChecked,
                at:
                    0,
                effectiveRange:
                    nil
            )
                as? Bool,
            false
        )

        let importedCheckedLocation =
            (imported.string as NSString)
                .range(
                    of:
                        "Checked item"
                )
                .location

        XCTAssertNotEqual(
            importedCheckedLocation,
            NSNotFound
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterChecklist,
                at:
                    importedCheckedLocation,
                effectiveRange:
                    nil
            )
                as? Bool,
            true
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterChecklistChecked,
                at:
                    importedCheckedLocation,
                effectiveRange:
                    nil
            )
                as? Bool,
            true
        )
    }

    func testOrdinaryBulletDOCXDoesNotBecomeChecklist() throws {
        let (view, controller) =
            editor(
                "Ordinary bullet\n"
            )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        controller.toggleBulletList()

        let source =
            NSAttributedString(
                attributedString:
                    try XCTUnwrap(
                        view.textStorage
                    )
            )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Ordinary List"
            )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertNotEqual(
            imported.attribute(
                .boldWriterChecklist,
                at:
                    0,
                effectiveRange:
                    nil
            )
                as? Bool,
            true
        )

        let style =
            try XCTUnwrap(
                imported.attribute(
                    .paragraphStyle,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? NSParagraphStyle
            )

        XCTAssertFalse(
            try XCTUnwrap(
                style.textLists.last
            )
                .isOrdered
        )
    }

    func testSwitchingChecklistToBulletClearsChecklistIdentity() throws {
        let (view, controller) =
            editor(
                "Convert me\n"
            )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        controller.toggleChecklist()
        controller.toggleBulletList()

        XCTAssertNotEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        let style =
            try XCTUnwrap(
                view.textStorage?
                    .attribute(
                        .paragraphStyle,
                        at:
                            0,
                        effectiveRange:
                            nil
                    )
                    as? NSParagraphStyle
            )

        XCTAssertFalse(
            try XCTUnwrap(
                style.textLists.last
            )
                .isOrdered
        )
    }


}
