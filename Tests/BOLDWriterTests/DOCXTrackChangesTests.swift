import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class DOCXTrackChangesTests: XCTestCase {
    private func trackedText()
        -> NSMutableAttributedString {
        let text =
            NSMutableAttributedString(
                string: "old new",
                attributes: [
                    .font:
                        NSFont.systemFont(ofSize: 15),
                    .foregroundColor:
                        NSColor.textColor
                ]
            )

        text.addAttribute(
            .boldWriterTrackChange,
            value: TrackChanges.marker(
                kind: .deletion,
                author: "Delete Author",
                date: Date(
                    timeIntervalSince1970:
                        1_700_000_000
                )
            ),
            range: NSRange(
                location: 0,
                length: 3
            )
        )

        text.addAttribute(
            .boldWriterTrackChange,
            value: TrackChanges.marker(
                kind: .insertion,
                author: "Insert Author",
                date: Date(
                    timeIntervalSince1970:
                        1_700_000_100
                )
            ),
            range: NSRange(
                location: 4,
                length: 3
            )
        )

        return text
    }

    private func documentXML(
        _ data: Data
    ) throws -> XMLDocument {
        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        return try DOCXPackage.xml(
            XCTUnwrap(
                parts["word/document.xml"]
            )
        )
    }

    func testDOCXExportsNativeInsertionAndDeletionMarkup()
        throws {
        let xml =
            try documentXML(
                DOCXExporter.data(
                    from: trackedText(),
                    title: "Tracked"
                )
            )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            ).count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='del']"
            ).count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='delText']"
            ).count,
            1
        )

        let insertion =
            try XCTUnwrap(
                try xml.nodes(
                    forXPath:
                        "//*[local-name()='ins']"
                ).first as? XMLElement
            )

        XCTAssertEqual(
            insertion.attributes?.first {
                $0.localName == "author"
            }?.stringValue,
            "Insert Author"
        )
    }

    func testTrackedDOCXIncludesTrackRevisionsSettings()
        throws {
        let data =
            try DOCXExporter.data(
                from: trackedText(),
                title: "Tracked Settings"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let settingsData =
            try XCTUnwrap(
                parts["word/settings.xml"]
            )

        let settingsXML =
            try DOCXPackage.xml(
                settingsData
            )

        XCTAssertEqual(
            try settingsXML.nodes(
                forXPath:
                    "//*[local-name()='trackRevisions']"
            ).count,
            1
        )

        let relationships =
            String(
                decoding:
                    try XCTUnwrap(
                        parts[
                            "word/_rels/document.xml.rels"
                        ]
                    ),
                as: UTF8.self
            )

        XCTAssertTrue(
            relationships.contains(
                "relationships/settings"
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Target=\"settings.xml\""
            )
        )

        let contentTypes =
            String(
                decoding:
                    try XCTUnwrap(
                        parts["[Content_Types].xml"]
                    ),
                as: UTF8.self
            )

        XCTAssertTrue(
            contentTypes.contains(
                "/word/settings.xml"
            )
        )

        XCTAssertTrue(
            contentTypes.contains(
                "wordprocessingml.settings+xml"
            )
        )
    }

    func testUntrackedDOCXOmitsTrackRevisionsSettings()
        throws {
        let text =
            NSAttributedString(
                string: "Plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let data =
            try DOCXExporter.data(
                from: text,
                title: "Plain Settings"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        XCTAssertNil(
            parts["word/settings.xml"]
        )

        let relationships =
            String(
                decoding:
                    try XCTUnwrap(
                        parts[
                            "word/_rels/document.xml.rels"
                        ]
                    ),
                as: UTF8.self
            )

        XCTAssertFalse(
            relationships.contains(
                "relationships/settings"
            )
        )

        XCTAssertFalse(
            relationships.contains(
                "Target=\"settings.xml\""
            )
        )

        let contentTypes =
            String(
                decoding:
                    try XCTUnwrap(
                        parts["[Content_Types].xml"]
                    ),
                as: UTF8.self
            )

        XCTAssertFalse(
            contentTypes.contains(
                "/word/settings.xml"
            )
        )

        XCTAssertFalse(
            contentTypes.contains(
                "wordprocessingml.settings+xml"
            )
        )
    }

    func testDOCXImporterDetectsTrackRevisionsSetting()
        throws {
        let tracked =
            try DOCXExporter.data(
                from: trackedText(),
                title: "Tracked Detection"
            )

        XCTAssertTrue(
            try DOCXImporter
                .trackChangesEnabled(
                    from: tracked
                )
        )

        let plain =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string: "Plain"
                    ),
                title: "Plain Detection"
            )

        XCTAssertFalse(
            try DOCXImporter
                .trackChangesEnabled(
                    from: plain
                )
        )
    }

    func testImportedDOCXRestoresTrackingStateIntoDocumentMetadata()
        throws {
        let trackedData =
            try DOCXExporter.data(
                from: trackedText(),
                title: "Tracked Import"
            )

        let trackedWrapper =
            FileWrapper(
                regularFileWithContents:
                    trackedData
            )

        trackedWrapper.preferredFilename =
            "Tracked.docx"

        let trackedDocument =
            try BOLDWriterDocument(
                fileWrapper:
                    trackedWrapper,
                contentType: .docx
            )

        XCTAssertEqual(
            trackedDocument
                .metadata
                .trackChangesEnabled,
            true
        )

        XCTAssertEqual(
            TrackChanges.records(
                in: trackedDocument.text
            ).count,
            2
        )

        let plainData =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string: "Plain"
                    ),
                title: "Plain Import"
            )

        let plainWrapper =
            FileWrapper(
                regularFileWithContents:
                    plainData
            )

        plainWrapper.preferredFilename =
            "Plain.docx"

        let plainDocument =
            try BOLDWriterDocument(
                fileWrapper:
                    plainWrapper,
                contentType: .docx
            )

        XCTAssertEqual(
            plainDocument
                .metadata
                .trackChangesEnabled,
            false
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: plainDocument.text
            ).isEmpty
        )
    }

    func testDOCXRoundTripRestoresTrackedChanges()
        throws {
        let restored =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from: trackedText(),
                        title: "Tracked"
                    )
            )

        XCTAssertEqual(
            restored.string,
            "old new"
        )

        let records =
            TrackChanges.records(in: restored)

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records.map(\.kind),
            [.deletion, .insertion]
        )

        XCTAssertEqual(
            records.map(\.author),
            [
                "Delete Author",
                "Insert Author"
            ]
        )
    }

    func testDOCXRoundTripKeepsFormattingInsideRevision()
        throws {
        let text =
            NSMutableAttributedString(
                string: "Bold",
                attributes: [
                    .font:
                        NSFont.boldSystemFont(
                            ofSize: 18
                        )
                ]
            )

        text.addAttribute(
            .boldWriterTrackChange,
            value: TrackChanges.marker(
                kind: .insertion,
                author: "Editor"
            ),
            range: NSRange(
                location: 0,
                length: text.length
            )
        )

        let restored =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from: text,
                        title: "Formatting"
                    )
            )

        XCTAssertEqual(
            restored.string,
            "Bold"
        )

        let font =
            try XCTUnwrap(
                restored.attribute(
                    .font,
                    at: 0,
                    effectiveRange: nil
                ) as? NSFont
            )

        XCTAssertTrue(
            NSFontManager.shared
                .traits(of: font)
                .contains(.boldFontMask)
        )

        XCTAssertEqual(
            TrackChanges.records(
                in: restored
            ).first?.kind,
            .insertion
        )
    }

    func testUntrackedDOCXDoesNotGainRevisionMetadata()
        throws {
        let text =
            NSAttributedString(
                string: "Plain",
                attributes: [
                    .font:
                        NSFont.systemFont(ofSize: 15)
                ]
            )

        let restored =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from: text,
                        title: "Plain"
                    )
            )

        XCTAssertEqual(
            restored.string,
            "Plain"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: restored
            ).isEmpty
        )
    }

    func testTrackingEnabledWithoutRevisionsExportsTrackRevisionsSetting()
        throws {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string: "No revisions yet"
                )
        )

        document.metadata
            .trackChangesEnabled = true

        let data =
            try ExportService.data(
                for: .docx,
                document: document
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let settingsData =
            try XCTUnwrap(
                parts["word/settings.xml"]
            )

        let settingsXML =
            try DOCXPackage.xml(
                settingsData
            )

        XCTAssertEqual(
            try settingsXML.nodes(
                forXPath:
                    "//*[local-name()='trackRevisions']"
            ).count,
            1
        )

        XCTAssertTrue(
            try DOCXImporter
                .trackChangesEnabled(
                    from: data
                )
        )

        let main =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertTrue(
            try main.nodes(
                forXPath:
                    "//*[local-name()='ins' or local-name()='del']"
            ).isEmpty
        )
    }

    func testTrackingDisabledWithExistingRevisionsPreservesMarkupButOmitsTrackRevisionsSetting()
        throws {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                trackedText()
        )

        document.metadata
            .trackChangesEnabled = false

        let data =
            try ExportService.data(
                for: .docx,
                document: document
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        XCTAssertNil(
            parts["word/settings.xml"]
        )

        XCTAssertFalse(
            try DOCXImporter
                .trackChangesEnabled(
                    from: data
                )
        )

        let main =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            ).count,
            1
        )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='del']"
            ).count,
            1
        )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='delText']"
            ).count,
            1
        )

        let contentTypes =
            String(
                decoding:
                    try XCTUnwrap(
                        parts[
                            "[Content_Types].xml"
                        ]
                    ),
                as: UTF8.self
            )

        XCTAssertFalse(
            contentTypes.contains(
                "/word/settings.xml"
            )
        )

        let relationships =
            String(
                decoding:
                    try XCTUnwrap(
                        parts[
                            "word/_rels/document.xml.rels"
                        ]
                    ),
                as: UTF8.self
            )

        XCTAssertFalse(
            relationships.contains(
                "/settings"
            )
        )
    }



    func testTrackedPageBreakRoundTripPreservesRevisionBoundary()
        throws {
        let text =
            NSMutableAttributedString(
                string:
                    "Before\u{000C}After",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let breakLocation =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "\u{000C}"
            )
            .location

        XCTAssertNotEqual(
            breakLocation,
            NSNotFound
        )

        text.addAttribute(
            .boldWriterTrackChange,
            value:
                TrackChanges.marker(
                    kind: .insertion,
                    author:
                        "Page Break Editor"
                ),
            range:
                NSRange(
                    location:
                        breakLocation,
                    length: 1
                )
        )

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Tracked Page Break"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let xml =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let insertions =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            )

        XCTAssertEqual(
            insertions.count,
            1
        )

        let insertion =
            try XCTUnwrap(
                insertions.first
                    as? XMLElement
            )

        XCTAssertEqual(
            try insertion.nodes(
                forXPath:
                    ".//*[local-name()='br' and @*[local-name()='type']='page']"
            ).count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from: data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let records =
            TrackChanges.records(
                in: restored
            )

        XCTAssertEqual(
            records.count,
            1
        )

        let record =
            try XCTUnwrap(
                records.first
            )

        XCTAssertEqual(
            record.kind,
            .insertion
        )

        XCTAssertEqual(
            record.author,
            "Page Break Editor"
        )

        XCTAssertEqual(
            record.length,
            1
        )

        XCTAssertEqual(
            (
                restored.string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            record.location,
                        length:
                            record.length
                    )
            ),
            "\u{000C}"
        )
    }

    func testTrackedTabsAndLineBreaksRoundTripInsideSingleRevision()
        throws {
        let trackedValue =
            "alpha\tbeta\u{2028}gamma"

        let text =
            NSMutableAttributedString(
                string:
                    "Before "
                    + trackedValue
                    + " After",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let trackedRange =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    trackedValue
            )

        XCTAssertNotEqual(
            trackedRange.location,
            NSNotFound
        )

        text.addAttribute(
            .boldWriterTrackChange,
            value:
                TrackChanges.marker(
                    kind: .deletion,
                    author:
                        "Structure Editor"
                ),
            range:
                trackedRange
        )

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Tracked Controls"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let xml =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let deletions =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='del']"
            )

        XCTAssertEqual(
            deletions.count,
            1
        )

        let deletion =
            try XCTUnwrap(
                deletions.first
                    as? XMLElement
            )

        XCTAssertEqual(
            try deletion.nodes(
                forXPath:
                    ".//*[local-name()='tab']"
            ).count,
            1
        )

        XCTAssertEqual(
            try deletion.nodes(
                forXPath:
                    ".//*[local-name()='br' and not(@*[local-name()='type']='page')]"
            ).count,
            1
        )

        XCTAssertGreaterThanOrEqual(
            try deletion.nodes(
                forXPath:
                    ".//*[local-name()='delText']"
            ).count,
            2
        )

        let restored =
            try DOCXImporter.text(
                from: data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let records =
            TrackChanges.records(
                in: restored
            )

        XCTAssertEqual(
            records.count,
            1
        )

        let record =
            try XCTUnwrap(
                records.first
            )

        XCTAssertEqual(
            record.kind,
            .deletion
        )

        XCTAssertEqual(
            record.author,
            "Structure Editor"
        )

        XCTAssertEqual(
            (
                restored.string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            record.location,
                        length:
                            record.length
                    )
            ),
            trackedValue
        )
    }



    func testTrackedInsertionInsideNativeNumberedListRoundTrips()
        throws {
        let style =
            NSMutableParagraphStyle()

        let list =
            NSTextList(
                markerFormat: .decimal,
                options: 0
            )

        list.startingItemNumber = 4
        style.textLists = [list]
        style.headIndent = 36
        style.firstLineHeadIndent = 18

        let text =
            NSMutableAttributedString(
                string:
                    "First item\nSecond item",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        ),
                    .paragraphStyle:
                        style
                ]
            )

        let trackedRange =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "Second"
            )

        XCTAssertNotEqual(
            trackedRange.location,
            NSNotFound
        )

        text.addAttribute(
            .boldWriterTrackChange,
            value:
                TrackChanges.marker(
                    kind: .insertion,
                    author:
                        "List Editor"
                ),
            range:
                trackedRange
        )

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Tracked Numbered List"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let numbering =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/numbering.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='numPr']"
            ).count,
            2
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='ins']//*[local-name()='t' and contains(text(),'Second')]"
            ).count,
            1
        )

        XCTAssertEqual(
            try numbering.nodes(
                forXPath:
                    "//*[local-name()='startOverride' and @*[local-name()='val']='4']"
            ).count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from: data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let restoredFirstStyle =
            try XCTUnwrap(
                restored.attribute(
                    .paragraphStyle,
                    at: 0,
                    effectiveRange: nil
                )
                    as? NSParagraphStyle
            )

        let secondLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Second item"
            )
            .location

        XCTAssertNotEqual(
            secondLocation,
            NSNotFound
        )

        let restoredSecondStyle =
            try XCTUnwrap(
                restored.attribute(
                    .paragraphStyle,
                    at:
                        secondLocation,
                    effectiveRange: nil
                )
                    as? NSParagraphStyle
            )

        XCTAssertEqual(
            restoredFirstStyle
                .textLists
                .last?
                .isOrdered,
            true
        )

        XCTAssertEqual(
            restoredSecondStyle
                .textLists
                .last?
                .isOrdered,
            true
        )

        XCTAssertEqual(
            restoredFirstStyle
                .textLists
                .last?
                .startingItemNumber,
            4
        )

        XCTAssertEqual(
            restoredSecondStyle
                .textLists
                .last?
                .startingItemNumber,
            4
        )

        let revisions =
            TrackChanges.records(
                in: restored
            )

        XCTAssertEqual(
            revisions.count,
            1
        )

        let revision =
            try XCTUnwrap(
                revisions.first
            )

        XCTAssertEqual(
            revision.kind,
            .insertion
        )

        XCTAssertEqual(
            revision.author,
            "List Editor"
        )

        XCTAssertEqual(
            (
                restored.string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            revision.location,
                        length:
                            revision.length
                    )
            ),
            "Second"
        )
    }

    func testTrackedDeletionInsideNativeBulletListRoundTrips()
        throws {
        let style =
            NSMutableParagraphStyle()

        let list =
            NSTextList(
                markerFormat: .disc,
                options: 0
            )

        style.textLists = [list]
        style.headIndent = 36
        style.firstLineHeadIndent = 18

        let text =
            NSMutableAttributedString(
                string:
                    "Alpha item\nBeta item",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        ),
                    .paragraphStyle:
                        style
                ]
            )

        let trackedRange =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "Alpha"
            )

        XCTAssertNotEqual(
            trackedRange.location,
            NSNotFound
        )

        text.addAttribute(
            .boldWriterTrackChange,
            value:
                TrackChanges.marker(
                    kind: .deletion,
                    author:
                        "Bullet Editor"
                ),
            range:
                trackedRange
        )

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Tracked Bullet List"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='numPr']"
            ).count,
            2
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='del']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='del']//*[local-name()='delText' and contains(text(),'Alpha')]"
            ).count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from: data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let betaLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Beta item"
            )
            .location

        XCTAssertNotEqual(
            betaLocation,
            NSNotFound
        )

        for location in [
            0,
            betaLocation
        ] {
            let paragraph =
                try XCTUnwrap(
                    restored.attribute(
                        .paragraphStyle,
                        at: location,
                        effectiveRange: nil
                    )
                        as? NSParagraphStyle
                )

            XCTAssertEqual(
                paragraph
                    .textLists
                    .last?
                    .isOrdered,
                false
            )
        }

        let revisions =
            TrackChanges.records(
                in: restored
            )

        XCTAssertEqual(
            revisions.count,
            1
        )

        let revision =
            try XCTUnwrap(
                revisions.first
            )

        XCTAssertEqual(
            revision.kind,
            .deletion
        )

        XCTAssertEqual(
            revision.author,
            "Bullet Editor"
        )

        XCTAssertEqual(
            (
                restored.string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            revision.location,
                        length:
                            revision.length
                    )
            ),
            "Alpha"
        )
    }



    func testImportsWordNativeRunPropertyChangeAsFormattingRevision()
        throws {

        let source =
            NSAttributedString(
                string:
                    "Hello",
                attributes: [
                    .font:
                        NSFont.boldSystemFont(
                            ofSize: 15
                        )
                ]
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    DOCXExporter.data(
                        from:
                            source,
                        title:
                            "Word Run Formatting Revision"
                    )
            )

        let mainIndex =
            try XCTUnwrap(
                entries.firstIndex(
                    where: {
                        $0.path
                            == "word/document.xml"
                    }
                )
            )

        let document =
            try DOCXPackage.xml(
                entries[
                    mainIndex
                ]
                .data
            )

        let run =
            try XCTUnwrap(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='r' and .//*[local-name()='t']]"
                )
                .first
                    as? XMLElement
            )

        let currentProperties =
            try XCTUnwrap(
                (run.children ?? [])
                    .compactMap {
                        $0 as? XMLElement
                    }
                    .first(
                        where: {
                            $0.localName
                                == "rPr"
                        }
                    )
            )

        // Build Word's PREVIOUS formatting by copying the
        // current run properties and removing bold.
        let previousProperties =
            try XCTUnwrap(
                currentProperties
                    .copy()
                    as? XMLElement
            )

        let boldIndexes =
            (previousProperties
                .children
                ?? [])
            .enumerated()
            .compactMap {
                index,
                child -> Int? in

                [
                    "b",
                    "bCs"
                ]
                .contains(
                    child.localName
                        ?? ""
                )
                    ? index
                    : nil
            }
            .reversed()

        for index in boldIndexes {
            previousProperties
                .removeChild(
                    at:
                        index
                )
        }

        let change =
            XMLElement(
                name:
                    "w:rPrChange"
            )

        change.addAttribute(
            XMLNode.attribute(
                withName:
                    "w:id",
                stringValue:
                    "42"
            ) as! XMLNode
        )

        change.addAttribute(
            XMLNode.attribute(
                withName:
                    "w:author",
                stringValue:
                    "Word Reviewer"
            ) as! XMLNode
        )

        let rawDate =
            "2026-09-18T12:34:56Z"

        change.addAttribute(
            XMLNode.attribute(
                withName:
                    "w:date",
                stringValue:
                    rawDate
            ) as! XMLNode
        )

        change.addChild(
            previousProperties
        )

        currentProperties.addChild(
            change
        )

        entries[
            mainIndex
        ]
        .data =
            document.xmlData

        let wordData =
            ZipArchiveWriter.archive(
                entries
            )

        let restored =
            try DOCXImporter.text(
                from:
                    wordData
            )

        // BOLD's internal formatting-revision representation
        // temporarily contains old text + proposed text.
        XCTAssertEqual(
            restored.string,
            "HelloHello"
        )

        let records =
            TrackChanges.records(
                in:
                    restored
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records.map(
                \.kind
            ),
            [
                .deletion,
                .insertion
            ]
        )

        XCTAssertEqual(
            Set(
                records.map(
                    \.id
                )
            )
            .count,
            1
        )

        XCTAssertEqual(
            Set(
                records.map(
                    \.author
                )
            ),
            [
                "Word Reviewer"
            ]
        )

        let expectedDate =
            try XCTUnwrap(
                ISO8601DateFormatter()
                    .date(
                        from:
                            rawDate
                    )
            )

        for record in records {
            XCTAssertEqual(
                record.date,
                expectedDate
            )
        }

        let reviewItems =
            TrackChanges.reviewItems(
                in:
                    restored
            )

        XCTAssertEqual(
            reviewItems.count,
            1
        )

        let item =
            try XCTUnwrap(
                reviewItems.first
            )

        XCTAssertEqual(
            item.kind,
            .formatting
        )

        XCTAssertEqual(
            item.title,
            "Formatting change"
        )

        XCTAssertEqual(
            item.author,
            "Word Reviewer"
        )

        XCTAssertEqual(
            item.date,
            expectedDate
        )

        XCTAssertEqual(
            item.preview,
            "Hello"
        )

        func isBold(
            at location: Int
        ) -> Bool {
            guard
                let font =
                    restored.attribute(
                        .font,
                        at:
                            location,
                        effectiveRange:
                            nil
                    )
                        as? NSFont
            else {
                return false
            }

            return
                NSFontManager.shared
                    .traits(
                        of:
                            font
                    )
                    .contains(
                        .boldFontMask
                    )
        }

        // Previous formatting is normal.
        XCTAssertFalse(
            isBold(
                at: 0
            )
        )

        // Current/proposed formatting remains bold.
        XCTAssertTrue(
            isBold(
                at: 5
            )
        )
    }


    func testImportsWordNativeParagraphPropertyChangeAsFormattingRevision()
        throws {

        func wordParagraphRevision(
            source:
                NSAttributedString,
            paragraphIndex:
                Int,
            revisionID:
                String
        ) throws -> Data {

            var entries =
                try DOCXPackage.entries(
                    in:
                        DOCXExporter.data(
                            from:
                                source,
                            title:
                                "Word Paragraph Formatting Revision"
                        )
                )

            let mainIndex =
                try XCTUnwrap(
                    entries.firstIndex(
                        where: {
                            $0.path
                                == "word/document.xml"
                        }
                    )
                )

            let document =
                try DOCXPackage.xml(
                    entries[
                        mainIndex
                    ]
                    .data
                )

            let paragraphs =
                try document.nodes(
                    forXPath:
                        "//*[local-name()='body']/*[local-name()='p']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            XCTAssertGreaterThan(
                paragraphs.count,
                paragraphIndex
            )

            let paragraph =
                paragraphs[
                    paragraphIndex
                ]

            let currentProperties =
                try XCTUnwrap(
                    (paragraph.children
                        ?? [])
                    .compactMap {
                        $0 as? XMLElement
                    }
                    .first(
                        where: {
                            $0.localName
                                == "pPr"
                        }
                    )
                )

            // Word's pPrChange contains the PREVIOUS paragraph
            // properties. Build a plain/default previous state by
            // removing alignment, indentation, and spacing from a
            // copy of the current pPr.
            let previousProperties =
                try XCTUnwrap(
                    currentProperties
                        .copy()
                        as? XMLElement
                )

            let removableNames:
                Set<String> = [
                    "jc",
                    "ind",
                    "spacing"
                ]

            let removableIndexes =
                (previousProperties.children
                    ?? [])
                .enumerated()
                .compactMap {
                    index,
                    child -> Int? in

                    removableNames.contains(
                        child.localName
                            ?? ""
                    )
                        ? index
                        : nil
                }
                .sorted(
                    by: >
                )

            for index in removableIndexes {
                previousProperties
                    .removeChild(
                        at:
                            index
                    )
            }

            let change =
                XMLElement(
                    name:
                        "w:pPrChange"
                )

            change.addAttribute(
                XMLNode.attribute(
                    withName:
                        "w:id",
                    stringValue:
                        revisionID
                ) as! XMLNode
            )

            change.addAttribute(
                XMLNode.attribute(
                    withName:
                        "w:author",
                    stringValue:
                        "Paragraph Reviewer"
                ) as! XMLNode
            )

            change.addAttribute(
                XMLNode.attribute(
                    withName:
                        "w:date",
                    stringValue:
                        "2026-09-18T15:00:00Z"
                ) as! XMLNode
            )

            change.addChild(
                previousProperties
            )

            currentProperties.addChild(
                change
            )

            entries[
                mainIndex
            ]
            .data =
                document.xmlData

            return
                ZipArchiveWriter.archive(
                    entries
                )
        }

        // ----------------------------------------------------
        // Non-final paragraph:
        // preserve old/new paragraph breaks and native style.
        // ----------------------------------------------------

        do {
            let source =
                NSMutableAttributedString(
                    string:
                        "Alpha\nBeta",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            let currentStyle =
                NSMutableParagraphStyle()

            currentStyle.alignment =
                .center

            currentStyle.headIndent =
                36

            currentStyle.firstLineHeadIndent =
                18

            currentStyle.paragraphSpacingBefore =
                6

            currentStyle.paragraphSpacing =
                10

            source.addAttribute(
                .paragraphStyle,
                value:
                    currentStyle,
                range:
                    NSRange(
                        location: 0,
                        length: 6
                    )
            )

            let restored =
                try DOCXImporter.text(
                    from:
                        wordParagraphRevision(
                            source:
                                source,
                            paragraphIndex:
                                0,
                            revisionID:
                                "77"
                        )
                )

            XCTAssertEqual(
                restored.string,
                "Alpha\nAlpha\nBeta"
            )

            let records =
                TrackChanges.records(
                    in:
                        restored
                )

            XCTAssertEqual(
                records.count,
                2
            )

            XCTAssertEqual(
                Set(
                    records.map(
                        \.id
                    )
                )
                .count,
                1
            )

            let deletion =
                try XCTUnwrap(
                    records.first(
                        where: {
                            $0.kind
                                == .deletion
                        }
                    )
                )

            let insertion =
                try XCTUnwrap(
                    records.first(
                        where: {
                            $0.kind
                                == .insertion
                        }
                    )
                )

            XCTAssertEqual(
                (
                    restored.string
                        as NSString
                )
                .substring(
                    with:
                        NSRange(
                            location:
                                deletion.location,
                            length:
                                deletion.length
                        )
                ),
                "Alpha\n"
            )

            XCTAssertEqual(
                (
                    restored.string
                        as NSString
                )
                .substring(
                    with:
                        NSRange(
                            location:
                                insertion.location,
                            length:
                                insertion.length
                        )
                ),
                "Alpha\n"
            )

            XCTAssertEqual(
                deletion.author,
                "Paragraph Reviewer"
            )

            XCTAssertEqual(
                insertion.author,
                "Paragraph Reviewer"
            )

            let items =
                TrackChanges.reviewItems(
                    in:
                        restored
                )

            XCTAssertEqual(
                items.count,
                1
            )

            XCTAssertEqual(
                items.first?.kind,
                .formatting
            )

            XCTAssertEqual(
                items.first?.title,
                "Formatting change"
            )

            let previousStyle =
                restored.attribute(
                    .paragraphStyle,
                    at:
                        deletion.location,
                    effectiveRange:
                        nil
                )
                    as? NSParagraphStyle

            let proposedStyle =
                try XCTUnwrap(
                    restored.attribute(
                        .paragraphStyle,
                        at:
                            insertion.location,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )

            XCTAssertNotEqual(
                previousStyle?
                    .alignment,
                .center
            )

            XCTAssertEqual(
                proposedStyle.alignment,
                .center
            )

            XCTAssertEqual(
                proposedStyle.headIndent,
                36,
                accuracy:
                    0.5
            )

            XCTAssertEqual(
                proposedStyle
                    .paragraphSpacingBefore,
                6,
                accuracy:
                    0.5
            )

            XCTAssertEqual(
                proposedStyle
                    .paragraphSpacing,
                10,
                accuracy:
                    0.5
            )
        }

        // ----------------------------------------------------
        // Final paragraph:
        // Word's synthetic final paragraph terminator is removed
        // by BOLD. The imported formatting pair must still remain
        // equal-length, adjacent, and reviewable.
        // ----------------------------------------------------

        do {
            let style =
                NSMutableParagraphStyle()

            style.alignment =
                .right

            style.headIndent =
                24

            let source =
                NSAttributedString(
                    string:
                        "Solo",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            ),
                        .paragraphStyle:
                            style
                    ]
                )

            let restored =
                try DOCXImporter.text(
                    from:
                        wordParagraphRevision(
                            source:
                                source,
                            paragraphIndex:
                                0,
                            revisionID:
                                "88"
                        )
                )

            XCTAssertEqual(
                restored.string,
                "SoloSolo"
            )

            let records =
                TrackChanges.records(
                    in:
                        restored
                )

            XCTAssertEqual(
                records.count,
                2
            )

            XCTAssertEqual(
                records.map(
                    \.length
                ),
                [
                    4,
                    4
                ]
            )

            XCTAssertEqual(
                Set(
                    records.map(
                        \.id
                    )
                )
                .count,
                1
            )

            let items =
                TrackChanges.reviewItems(
                    in:
                        restored
                )

            XCTAssertEqual(
                items.count,
                1
            )

            XCTAssertEqual(
                items.first?.kind,
                .formatting
            )

            XCTAssertEqual(
                items.first?.preview,
                "Solo"
            )
        }
    }


    func testExportServiceWritesNativeWordComments()
        throws {

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "Alpha Beta Gamma"
                )
        )

        var comment =
            DocumentComment(
                text:
                    "Review & clarify <this>",
                location:
                    6,
                length:
                    4
            )

        comment.author =
            "Word Reviewer"

        comment.createdAt =
            Date(
                timeIntervalSince1970:
                    1_600_000_000
            )

        document.metadata.comments = [
            comment
        ]

        let data =
            try ExportService.data(
                for:
                    .docx,
                document:
                    document
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let comments =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/comments.xml"
                    ]
                )
            )

        let commentNodes =
            try comments.nodes(
                forXPath:
                    "//*[local-name()='comment']"
            )

        XCTAssertEqual(
            commentNodes.count,
            1
        )

        let commentNode =
            try XCTUnwrap(
                commentNodes.first
                    as? XMLElement
            )

        XCTAssertEqual(
            commentNode
                .attributes?
                .first {
                    $0.localName
                        == "id"
                }?
                .stringValue,
            "0"
        )

        XCTAssertEqual(
            commentNode
                .attributes?
                .first {
                    $0.localName
                        == "author"
                }?
                .stringValue,
            "Word Reviewer"
        )

        XCTAssertEqual(
            commentNode.stringValue,
            "Review & clarify <this>"
        )

        XCTAssertNotNil(
            commentNode
                .attributes?
                .first {
                    $0.localName
                        == "date"
                }?
                .stringValue
        )

        let main =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='commentRangeStart' and @*[local-name()='id']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='commentRangeEnd' and @*[local-name()='id']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='commentReference' and @*[local-name()='id']='0']"
            )
            .count,
            1
        )

        let relationships =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/_rels/document.xml.rels"
                    ]
                )
            )

        XCTAssertEqual(
            try relationships.nodes(
                forXPath:
                    "//*[local-name()='Relationship' and contains(@Type, '/comments') and @Target='comments.xml']"
            )
            .count,
            1
        )

        let contentTypes =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "[Content_Types].xml"
                    ]
                )
            )

        XCTAssertEqual(
            try contentTypes.nodes(
                forXPath:
                    "//*[local-name()='Override' and @PartName='/word/comments.xml']"
            )
            .count,
            1
        )
    }


    func testWordCommentsRoundTripIntoDocumentMetadata()
        throws {

        var rangeComment =
            DocumentComment(
                text:
                    "Review Beta",
                location:
                    6,
                length:
                    4
            )

        rangeComment.author =
            "Range Reviewer"

        rangeComment.createdAt =
            Date(
                timeIntervalSince1970:
                    1_600_000_000
            )

        var pointComment =
            DocumentComment(
                text:
                    "Point note",
                location:
                    5,
                length:
                    0
            )

        pointComment.author =
            "Point Reviewer"

        pointComment.createdAt =
            Date(
                timeIntervalSince1970:
                    1_600_000_100
            )

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Alpha Beta Gamma"
                    ),
                title:
                    "Comment Import",
                comments: [
                    rangeComment,
                    pointComment
                ]
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Comment Import.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        XCTAssertEqual(
            imported.text.string,
            "Alpha Beta Gamma"
        )

        XCTAssertEqual(
            imported.metadata.comments.count,
            2
        )

        let ranged =
            try XCTUnwrap(
                imported.metadata.comments
                    .first {
                        $0.text
                            == "Review Beta"
                    }
            )

        XCTAssertEqual(
            ranged.author,
            "Range Reviewer"
        )

        XCTAssertEqual(
            ranged.location,
            6
        )

        XCTAssertEqual(
            ranged.length,
            4
        )

        XCTAssertEqual(
            ranged.createdAt
                .timeIntervalSince1970,
            rangeComment.createdAt
                .timeIntervalSince1970,
            accuracy:
                1
        )

        let point =
            try XCTUnwrap(
                imported.metadata.comments
                    .first {
                        $0.text
                            == "Point note"
                    }
            )

        XCTAssertEqual(
            point.author,
            "Point Reviewer"
        )

        XCTAssertEqual(
            point.location,
            5
        )

        XCTAssertEqual(
            point.length,
            0
        )

        XCTAssertEqual(
            point.createdAt
                .timeIntervalSince1970,
            pointComment.createdAt
                .timeIntervalSince1970,
            accuracy:
                1
        )
    }

    func testWordCommentImportCoexistsWithTrackedChanges()
        throws {

        var comment =
            DocumentComment(
                text:
                    "Review inserted word",
                location:
                    4,
                length:
                    3
            )

        comment.author =
            "Revision Reviewer"

        comment.createdAt =
            Date(
                timeIntervalSince1970:
                    1_600_001_000
            )

        let data =
            try DOCXExporter.data(
                from:
                    trackedText(),
                title:
                    "Comments and Revisions",
                comments: [
                    comment
                ]
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Comments and Revisions.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        XCTAssertEqual(
            imported.text.string,
            "old new"
        )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    imported.text
            ).count,
            2
        )

        XCTAssertEqual(
            imported.metadata.comments.count,
            1
        )

        let restored =
            try XCTUnwrap(
                imported.metadata.comments
                    .first
            )

        XCTAssertEqual(
            restored.text,
            "Review inserted word"
        )

        XCTAssertEqual(
            restored.author,
            "Revision Reviewer"
        )

        XCTAssertEqual(
            restored.location,
            4
        )

        XCTAssertEqual(
            restored.length,
            3
        )

        XCTAssertEqual(
            (
                imported.text.string
                    as NSString
            )
            .substring(
                with:
                    NSRange(
                        location:
                            restored.location,
                        length:
                            restored.length
                    )
            ),
            "new"
        )
    }


    func testDOCXBookmarksRoundTripAsNativeWordBookmarks()
        throws {

        let original =
            DocumentBookmark(
                name:
                    "Opening",
                location:
                    6
            )

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Alpha Beta Gamma"
                    ),
                title:
                    "Bookmark Round Trip",
                bookmarks: [
                    original
                ]
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let documentXML =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let starts =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='bookmarkStart']"
            )

        let ends =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='bookmarkEnd']"
            )

        XCTAssertEqual(
            starts.count,
            1
        )

        XCTAssertEqual(
            ends.count,
            1
        )

        let start =
            try XCTUnwrap(
                starts.first
                    as? XMLElement
            )

        XCTAssertEqual(
            start.attributes?
                .first {
                    $0.localName
                        == "name"
                }?
                .stringValue,
            "Opening"
        )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Bookmark Round Trip.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        XCTAssertEqual(
            imported.text.string,
            "Alpha Beta Gamma"
        )

        XCTAssertEqual(
            imported.metadata.bookmarks.count,
            1
        )

        let restored =
            try XCTUnwrap(
                imported.metadata.bookmarks
                    .first
            )

        XCTAssertEqual(
            restored.name,
            "Opening"
        )

        XCTAssertEqual(
            restored.location,
            6
        )
    }

    func testWordBookmarkImportCoexistsWithCommentsAndTrackedChanges()
        throws {

        var comment =
            DocumentComment(
                text:
                    "Review new",
                location:
                    4,
                length:
                    3
            )

        comment.author =
            "Reviewer"

        let bookmark =
            DocumentBookmark(
                name:
                    "InsertedWord",
                location:
                    4
            )

        let data =
            try DOCXExporter.data(
                from:
                    trackedText(),
                title:
                    "Bookmark Revision Coexistence",
                comments: [
                    comment
                ],
                bookmarks: [
                    bookmark
                ]
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Bookmark Revision Coexistence.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        XCTAssertEqual(
            imported.text.string,
            "old new"
        )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    imported.text
            ).count,
            2
        )

        XCTAssertEqual(
            imported.metadata.comments.count,
            1
        )

        XCTAssertEqual(
            imported.metadata.comments
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            imported.metadata.comments
                .first?
                .length,
            3
        )

        XCTAssertEqual(
            imported.metadata.bookmarks.count,
            1
        )

        XCTAssertEqual(
            imported.metadata.bookmarks
                .first?
                .name,
            "InsertedWord"
        )

        XCTAssertEqual(
            imported.metadata.bookmarks
                .first?
                .location,
            4
        )
    }


    func testWordHyperlinkCoexistsWithCommentsBookmarksAndTrackedChanges()
        throws {

        let text =
            NSMutableAttributedString(
                attributedString:
                    trackedText()
            )

        text.addAttribute(
            .link,
            value:
                "#Inserted Word",
            range:
                NSRange(
                    location:
                        4,
                    length:
                        3
                )
        )

        var comment =
            DocumentComment(
                text:
                    "Review linked insertion",
                location:
                    4,
                length:
                    3
            )

        comment.author =
            "Link Reviewer"

        let bookmark =
            DocumentBookmark(
                name:
                    "Inserted Word",
                location:
                    4
            )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Linked Revision",
                comments: [
                    comment
                ],
                bookmarks: [
                    bookmark
                ]
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.text.string,
            "old new"
        )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    imported.text
            ).count,
            2
        )

        XCTAssertEqual(
            imported.comments.count,
            1
        )

        XCTAssertEqual(
            imported.comments
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            imported.comments
                .first?
                .length,
            3
        )

        XCTAssertEqual(
            imported.bookmarks.count,
            1
        )

        XCTAssertEqual(
            imported.bookmarks
                .first?
                .name,
            "Inserted_Word"
        )

        XCTAssertEqual(
            imported.bookmarks
                .first?
                .location,
            4
        )

        let value =
            imported.text.attribute(
                .link,
                at:
                    4,
                effectiveRange:
                    nil
            )

        let target =
            (value as? URL)?
                .absoluteString
            ?? value as? String

        XCTAssertEqual(
            target,
            "#Inserted_Word"
        )
    }


    func testDOCXNamedParagraphStylesRoundTripSemantically()
        throws {

        let original =
            NSMutableAttributedString()

        var starts:
            [(WriterStyle, Int)] = []

        for style
            in WriterStyle.allCases {

            let location =
                original.length

            starts.append(
                (
                    style,
                    location
                )
            )

            original.append(
                NSAttributedString(
                    string:
                        style.rawValue
                        + " paragraph\n",
                    attributes: [
                        .font:
                            style.font,
                        .boldWriterStyle:
                            style.rawValue
                    ]
                )
            )
        }

        let data =
            try DOCXExporter.data(
                from:
                    original,
                title:
                    "Named Styles"
            )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            imported.string,
            original.string
        )

        for (
            style,
            location
        ) in starts {

            XCTAssertEqual(
                imported.attribute(
                    .boldWriterStyle,
                    at:
                        location,
                    effectiveRange:
                        nil
                ) as? String,
                style.rawValue,
                "Lost semantic style \(style.rawValue)"
            )
        }
    }

    func testDOCXNamedStyleCanResolveExactWordStyleName()
        throws {

        let original =
            NSAttributedString(
                string:
                    "Custom Word heading\n",
                attributes: [
                    .font:
                        WriterStyle.heading1.font,
                    .boldWriterStyle:
                        WriterStyle.heading1.rawValue
                ]
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    DOCXExporter.data(
                        from:
                            original,
                        title:
                            "Named Style Name"
                    )
            )

        let documentIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/document.xml"
                }
            )

        let stylesIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/styles.xml"
                }
            )

        var documentXML =
            String(
                decoding:
                    entries[
                        documentIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        var stylesXML =
            String(
                decoding:
                    entries[
                        stylesIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        let originalDocumentXML =
            documentXML

        let originalStylesXML =
            stylesXML

        documentXML =
            documentXML
                .replacingOccurrences(
                    of:
                        "w:val=\"Heading1\"",
                    with:
                        "w:val=\"MyExactHeading\""
                )

        stylesXML =
            stylesXML
                .replacingOccurrences(
                    of:
                        "w:styleId=\"Heading1\"",
                    with:
                        "w:styleId=\"MyExactHeading\""
                )

        XCTAssertNotEqual(
            documentXML,
            originalDocumentXML
        )

        XCTAssertNotEqual(
            stylesXML,
            originalStylesXML
        )

        // The style ID is custom, but its exact Word w:name
        // remains "Heading 1". That exact semantic name is safe
        // to map.
        entries[
            documentIndex
        ]
        .data =
            Data(
                documentXML.utf8
            )

        entries[
            stylesIndex
        ]
        .data =
            Data(
                stylesXML.utf8
            )

        let imported =
            try DOCXImporter.text(
                from:
                    ZipArchiveWriter.archive(
                        entries
                    )
            )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterStyle,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            WriterStyle.heading1.rawValue
        )
    }

    func testDOCXUnknownCustomStyleStaysVisualOnly()
        throws {

        let original =
            NSAttributedString(
                string:
                    "Mystery styled text\n",
                attributes: [
                    .font:
                        WriterStyle.heading1.font,
                    .boldWriterStyle:
                        WriterStyle.heading1.rawValue
                ]
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    DOCXExporter.data(
                        from:
                            original,
                        title:
                            "Unknown Style"
                    )
            )

        let documentIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/document.xml"
                }
            )

        let stylesIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/styles.xml"
                }
            )

        var documentXML =
            String(
                decoding:
                    entries[
                        documentIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        var stylesXML =
            String(
                decoding:
                    entries[
                        stylesIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        documentXML =
            documentXML
                .replacingOccurrences(
                    of:
                        "w:val=\"Heading1\"",
                    with:
                        "w:val=\"MysteryStyle\""
                )

        stylesXML =
            stylesXML
                .replacingOccurrences(
                    of:
                        "w:styleId=\"Heading1\"",
                    with:
                        "w:styleId=\"MysteryStyle\""
                )
                .replacingOccurrences(
                    of:
                        "<w:name w:val=\"Heading 1\"/>",
                    with:
                        "<w:name w:val=\"Mystery Semantic\"/>"
                )

        entries[
            documentIndex
        ]
        .data =
            Data(
                documentXML.utf8
            )

        entries[
            stylesIndex
        ]
        .data =
            Data(
                stylesXML.utf8
            )

        let imported =
            try DOCXImporter.text(
                from:
                    ZipArchiveWriter.archive(
                        entries
                    )
            )

        XCTAssertNil(
            imported.attribute(
                .boldWriterStyle,
                at:
                    0,
                effectiveRange:
                    nil
            )
        )

        // Unknown semantic metadata must not strip the actual
        // rich formatting imported from the Word run.
        let font =
            try XCTUnwrap(
                imported.attribute(
                    .font,
                    at:
                        0,
                    effectiveRange:
                        nil
                ) as? NSFont
            )

        XCTAssertGreaterThan(
            font.pointSize,
            12
        )
    }

    func testDOCXNamedStyleSurvivesTrackedTextRevision()
        throws {

        let original =
            NSMutableAttributedString(
                attributedString:
                    trackedText()
            )

        original.addAttributes(
            [
                .font:
                    WriterStyle.heading2.font,
                .boldWriterStyle:
                    WriterStyle.heading2.rawValue
            ],
            range:
                NSRange(
                    location:
                        0,
                    length:
                        original.length
                )
        )

        let imported =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from:
                            original,
                        title:
                            "Styled Revision"
                    )
            )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    imported
            ).count,
            2
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterStyle,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            WriterStyle.heading2.rawValue
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterStyle,
                at:
                    min(
                        4,
                        imported.length
                            - 1
                    ),
                effectiveRange:
                    nil
            ) as? String,
            WriterStyle.heading2.rawValue
        )
    }


    func testDOCXNumberedListsPreserveRestartIdentity()
        throws {

        let firstStyle =
            NSMutableParagraphStyle()

        let firstList =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        firstList.startingItemNumber =
            5

        firstStyle.textLists =
            [
                firstList
            ]

        firstStyle.headIndent =
            36

        firstStyle.firstLineHeadIndent =
            18

        let restartedStyle =
            NSMutableParagraphStyle()

        let restartedList =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        restartedList.startingItemNumber =
            1

        restartedStyle.textLists =
            [
                restartedList
            ]

        restartedStyle.headIndent =
            36

        restartedStyle.firstLineHeadIndent =
            18

        let text =
            NSMutableAttributedString()

        text.append(
            NSAttributedString(
                string:
                    "Five\nSix\n",
                attributes: [
                    .paragraphStyle:
                        firstStyle,
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )
        )

        text.append(
            NSAttributedString(
                string:
                    "Body paragraph\n",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )
        )

        text.append(
            NSAttributedString(
                string:
                    "Restart one\nRestart two",
                attributes: [
                    .paragraphStyle:
                        restartedStyle,
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "List Restart Identity"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let numbering =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/numbering.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try numbering.nodes(
                forXPath:
                    "//*[local-name()='num']"
            )
            .count,
            2
        )

        XCTAssertEqual(
            try numbering.nodes(
                forXPath:
                    "//*[local-name()='startOverride' "
                    + "and @*[local-name()='val']='5']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try numbering.nodes(
                forXPath:
                    "//*[local-name()='startOverride' "
                    + "and @*[local-name()='val']='1']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        func list(
            at textValue: String
        ) throws -> NSTextList {
            let location =
                (
                    restored.string
                        as NSString
                )
                .range(
                    of:
                        textValue
                )
                .location

            XCTAssertNotEqual(
                location,
                NSNotFound
            )

            let paragraph =
                try XCTUnwrap(
                    restored.attribute(
                        .paragraphStyle,
                        at:
                            location,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )

            return try XCTUnwrap(
                paragraph.textLists.last
            )
        }

        let five =
            try list(
                at:
                    "Five"
            )

        let six =
            try list(
                at:
                    "Six"
            )

        let restartOne =
            try list(
                at:
                    "Restart one"
            )

        let restartTwo =
            try list(
                at:
                    "Restart two"
            )

        XCTAssertTrue(
            five === six
        )

        XCTAssertTrue(
            restartOne === restartTwo
        )

        XCTAssertFalse(
            five === restartOne
        )

        XCTAssertEqual(
            five.startingItemNumber,
            5
        )

        XCTAssertEqual(
            restartOne.startingItemNumber,
            1
        )

        XCTAssertTrue(
            five.isOrdered
        )

        XCTAssertTrue(
            restartOne.isOrdered
        )

        let bodyLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Body paragraph"
            )
            .location

        let bodyStyle =
            restored.attribute(
                .paragraphStyle,
                at:
                    bodyLocation,
                effectiveRange:
                    nil
            )
                as? NSParagraphStyle

        XCTAssertTrue(
            bodyStyle?
                .textLists
                .isEmpty
                ?? true
        )
    }

    func testDOCXBulletAndNumberedListsRemainSeparate()
        throws {

        let bulletStyle =
            NSMutableParagraphStyle()

        let bullets =
            NSTextList(
                markerFormat:
                    .disc,
                options:
                    0
            )

        bulletStyle.textLists =
            [
                bullets
            ]

        let numberedStyle =
            NSMutableParagraphStyle()

        let numbers =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        numbers.startingItemNumber =
            3

        numberedStyle.textLists =
            [
                numbers
            ]

        let text =
            NSMutableAttributedString(
                string:
                    "Bullet A\nBullet B\n",
                attributes: [
                    .paragraphStyle:
                        bulletStyle
                ]
            )

        text.append(
            NSAttributedString(
                string:
                    "Number 3\nNumber 4",
                attributes: [
                    .paragraphStyle:
                        numberedStyle
                ]
            )
        )

        let restored =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from:
                            text,
                        title:
                            "Mixed Lists"
                    )
            )

        let bullet =
            try XCTUnwrap(
                (
                    restored.attribute(
                        .paragraphStyle,
                        at:
                            0,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )?
                .textLists
                .last
            )

        let numberLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Number 3"
            )
            .location

        let number =
            try XCTUnwrap(
                (
                    restored.attribute(
                        .paragraphStyle,
                        at:
                            numberLocation,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )?
                .textLists
                .last
            )

        XCTAssertFalse(
            bullet.isOrdered
        )

        XCTAssertTrue(
            number.isOrdered
        )

        XCTAssertEqual(
            number.startingItemNumber,
            3
        )

        XCTAssertFalse(
            bullet === number
        )
    }

    func testDOCXListAndNamedParagraphStyleCoexist()
        throws {

        let paragraph =
            NSMutableParagraphStyle()

        let list =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        list.startingItemNumber =
            4

        paragraph.textLists =
            [
                list
            ]

        paragraph.headIndent =
            36

        paragraph.firstLineHeadIndent =
            18

        let text =
            NSMutableAttributedString(
                string:
                    "Styled item\nAnother styled item",
                attributes: [
                    .font:
                        WriterStyle.heading2.font,
                    .paragraphStyle:
                        paragraph,
                    .boldWriterStyle:
                        WriterStyle.heading2.rawValue
                ]
            )

        let restored =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from:
                            text,
                        title:
                            "Styled List"
                    )
            )

        for value in [
            "Styled item",
            "Another styled item"
        ] {
            let location =
                (
                    restored.string
                        as NSString
                )
                .range(
                    of:
                        value
                )
                .location

            XCTAssertNotEqual(
                location,
                NSNotFound
            )

            XCTAssertEqual(
                restored.attribute(
                    .boldWriterStyle,
                    at:
                        location,
                    effectiveRange:
                        nil
                ) as? String,
                WriterStyle.heading2.rawValue
            )

            let style =
                try XCTUnwrap(
                    restored.attribute(
                        .paragraphStyle,
                        at:
                            location,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )

            XCTAssertEqual(
                style.textLists.last?
                    .isOrdered,
                true
            )

            XCTAssertEqual(
                style.textLists.last?
                    .startingItemNumber,
                4
            )
        }
    }

    func testDOCXUnsupportedNumberFormatIsNotRepairedAsDecimal()
        throws {

        let style =
            NSMutableParagraphStyle()

        let list =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        style.textLists =
            [
                list
            ]

        let original =
            NSAttributedString(
                string:
                    "Alpha\nBeta",
                attributes: [
                    .paragraphStyle:
                        style
                ]
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    DOCXExporter.data(
                        from:
                            original,
                        title:
                            "Unsupported Number Format"
                    )
            )

        let numberingIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/numbering.xml"
                }
            )

        var numberingXML =
            String(
                decoding:
                    entries[
                        numberingIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        let before =
            numberingXML

        numberingXML =
            numberingXML
                .replacingOccurrences(
                    of:
                        "w:numFmt w:val=\"decimal\"",
                    with:
                        "w:numFmt w:val=\"lowerLetter\""
                )

        XCTAssertNotEqual(
            numberingXML,
            before
        )

        entries[
            numberingIndex
        ]
        .data =
            Data(
                numberingXML.utf8
            )

        let imported =
            try DOCXImporter.text(
                from:
                    ZipArchiveWriter.archive(
                        entries
                    )
            )

        XCTAssertEqual(
            imported.string,
            "Alpha\nBeta"
        )

        // This assertion deliberately does NOT demand a specific
        // AppKit interpretation of lowerLetter. The contract is
        // simply that BOLD's repair layer must not manufacture a
        // decimal list from an unsupported Word numbering format.
        //
        // If AppKit itself preserves a list, its native metadata
        // remains untouched. If it omits it, that is also safer
        // than falsely claiming BOLD decimal semantics.
        let firstStyle =
            imported.attribute(
                .paragraphStyle,
                at:
                    0,
                effectiveRange:
                    nil
            )
                as? NSParagraphStyle

        if let importedList =
            firstStyle?
                .textLists
                .last {

            let marker =
                importedList.markerFormat

            XCTAssertNotEqual(
                marker,
                .decimal
            )
        }
    }

    func testDOCXNestedWordLevelIsNotFlattenedByRepairLayer()
        throws {

        let style =
            NSMutableParagraphStyle()

        let list =
            NSTextList(
                markerFormat:
                    .decimal,
                options:
                    0
            )

        style.textLists =
            [
                list
            ]

        let original =
            NSAttributedString(
                string:
                    "Nested item",
                attributes: [
                    .paragraphStyle:
                        style
                ]
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    DOCXExporter.data(
                        from:
                            original,
                        title:
                            "Nested Word List"
                    )
            )

        let documentIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/document.xml"
                }
            )

        let numberingIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/numbering.xml"
                }
            )

        var documentXML =
            String(
                decoding:
                    entries[
                        documentIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        var numberingXML =
            String(
                decoding:
                    entries[
                        numberingIndex
                    ]
                    .data,
                as:
                    UTF8.self
            )

        let documentBefore =
            documentXML

        documentXML =
            documentXML
                .replacingOccurrences(
                    of:
                        "<w:ilvl w:val=\"0\"/>",
                    with:
                        "<w:ilvl w:val=\"1\"/>"
                )

        XCTAssertNotEqual(
            documentXML,
            documentBefore
        )

        let levelZero =
            #"<w:lvl w:ilvl="0">"#

        let levelOne =
            #"<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%2."/><w:lvlJc w:val="left"/><w:pPr><w:tabs><w:tab w:val="num" w:pos="1440"/></w:tabs><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>"#

        guard
            let insertion =
                numberingXML.range(
                    of:
                        "</w:abstractNum>"
                )
        else {
            XCTFail(
                "Missing abstract numbering definition"
            )

            return
        }

        // Ensure the target abstract definition actually exists.
        XCTAssertTrue(
            numberingXML.contains(
                levelZero
            )
        )

        numberingXML.insert(
            contentsOf:
                levelOne,
            at:
                insertion.lowerBound
        )

        entries[
            documentIndex
        ]
        .data =
            Data(
                documentXML.utf8
            )

        entries[
            numberingIndex
        ]
        .data =
            Data(
                numberingXML.utf8
            )

        let imported =
            try DOCXImporter.text(
                from:
                    ZipArchiveWriter.archive(
                        entries
                    )
            )

        XCTAssertEqual(
            imported.string,
            "Nested item"
        )

        // BOLD's repair layer supports level zero only. The test
        // intentionally avoids asserting what AppKit chooses to
        // preserve visually for ilvl=1; it verifies only that the
        // importer no longer forces its own flat decimal metadata.
        //
        // A level-1 Word paragraph must therefore not be replaced
        // with the exact BOLD level-zero list object produced by
        // restoreListMetadata. If AppKit leaves native nested
        // metadata, retain it untouched.
        let importedStyle =
            imported.attribute(
                .paragraphStyle,
                at:
                    0,
                effectiveRange:
                    nil
            )
                as? NSParagraphStyle

        if let native =
            importedStyle?
                .textLists
                .last {

            // AppKit is allowed to preserve a nested representation,
            // but BOLD must not normalize it to the exporter-style
            // level-zero decimal repair with 36/18-point indentation.
            let looksLikeBOLDFlatRepair =
                native.markerFormat
                    == .decimal
                && abs(
                    importedStyle?
                        .headIndent
                        ?? 0
                    - 36
                ) < 0.01
                && abs(
                    importedStyle?
                        .firstLineHeadIndent
                        ?? 0
                    - 18
                ) < 0.01

            XCTAssertFalse(
                looksLikeBOLDFlatRepair
            )
        }
    }

}
