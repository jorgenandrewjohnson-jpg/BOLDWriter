import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

final class PersistenceTests: XCTestCase {
    func testNativePackagePreservesRichTextAndMetadata() throws {
        let text = NSMutableAttributedString(string: "A styled heading\nBody")
        text.addAttributes([.font: NSFont.boldSystemFont(ofSize: 24), .boldWriterStyle: WriterStyle.heading1.rawValue], range: NSRange(location: 0, length: 17))
        var metadata = DocumentMetadata(title: "Round Trip")
        metadata.comments = [DocumentComment(text: "A comment", location: 0, length: 1)]
        metadata.bookmarks = [DocumentBookmark(name: "Start", location: 0)]
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        let children = try XCTUnwrap(package.fileWrappers)
        XCTAssertNotNil(children["content.rtfd"])
        let metadataData = try XCTUnwrap(children["metadata.json"]?.regularFileContents)
        let decodedMetadata = try JSONDecoder().decode(DocumentMetadata.self, from: metadataData)
        XCTAssertEqual(decodedMetadata.title, "Round Trip")
        XCTAssertEqual(decodedMetadata.comments.count, 1)
        XCTAssertEqual(decodedMetadata.styleRuns.first?.style, .heading1)
        let decodedText = try XCTUnwrap(NSAttributedString(rtfdFileWrapper: try XCTUnwrap(children["content.rtfd"]), documentAttributes: nil))
        XCTAssertEqual(decodedText.string, text.string)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, text.string)
        XCTAssertEqual(reopened.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertEqual(reopened.metadata.comments, metadata.comments)
        XCTAssertEqual(reopened.metadata.bookmarks, metadata.bookmarks)
    }

    func testRevisionHistoryIsCapped() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "safe"))
        for index in 0..<30 { document.createRevision(named: "Version \(index)") }
        XCTAssertEqual(document.metadata.revisions.count, 20)
        XCTAssertEqual(document.metadata.revisions.first?.name, "Version 29")
    }

    func testRevisionRestorePreservesAttachmentsAndDocumentMetadata() throws {
        let document = BOLDWriterDocument()
        let (originalText, imageData) = try makeAttachedText()
        document.replaceText(with: originalText)
        document.metadata.title = "Attachment Recovery"
        document.metadata.page = PageSettings(paper: .a4, landscape: true, topMargin: 33, bottomMargin: 44, leftMargin: 55, rightMargin: 66, showsPageNumbers: false, footerText: "Private footer")
        document.metadata.comments = [DocumentComment(text: "Keep this comment", location: 0, length: 7)]
        document.metadata.bookmarks = [DocumentBookmark(name: "Illustration", location: 13)]
        document.metadata.notes = "Private manuscript notes"
        let originalMetadata = document.metadata
        XCTAssertTrue(document.createRevision(named: "With illustration"))
        let storedRevision = try XCTUnwrap(document.metadata.revisions.first)
        let revision = try JSONDecoder().decode(RevisionRecord.self, from: JSONEncoder().encode(storedRevision))
        XCTAssertNotNil(revision.rtfdData)
        XCTAssertNotNil(revision.documentMetadata)

        document.replaceText(with: NSAttributedString(string: "Different writing"))
        document.metadata.title = "Changed title"
        document.metadata.page = PageSettings()
        document.metadata.comments = []
        document.metadata.bookmarks = []
        document.metadata.notes = "Changed notes"
        let changedRevisionID = document.revisionID
        try document.restore(revision)

        XCTAssertEqual(document.text.string, originalText.string)
        let attachment = try XCTUnwrap(document.text.attribute(.attachment, at: 13, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.fileWrapper?.regularFileContents, imageData)
        XCTAssertEqual(document.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertEqual(document.metadata.title, originalMetadata.title)
        XCTAssertEqual(document.metadata.page, originalMetadata.page)
        XCTAssertEqual(document.metadata.comments, originalMetadata.comments)
        XCTAssertEqual(document.metadata.bookmarks, originalMetadata.bookmarks)
        XCTAssertEqual(document.metadata.notes, originalMetadata.notes)
        XCTAssertNotEqual(document.revisionID, changedRevisionID)
        XCTAssertEqual(document.metadata.revisions.count, 2)
        XCTAssertEqual(document.metadata.revisions.first?.name, "Before restoring With illustration")
    }

    func testStandaloneRTFDImportPreservesAttachment() throws {
        let (text, imageData) = try makeAttachedText()
        let wrapper = try text.fileWrapper(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        wrapper.preferredFilename = "Imported Illustration.rtfd"
        let document = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .rtfd)
        XCTAssertEqual(document.text.string, text.string)
        let attachment = try XCTUnwrap(document.text.attribute(.attachment, at: 13, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.fileWrapper?.regularFileContents, imageData)
    }

    func testNativeImportIgnoresNegativeOverflowAndOutOfBoundsStyleRuns() throws {
        let text = NSAttributedString(string: "Safe text", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata())
        var metadata = DocumentMetadata()
        metadata.styleRuns = malformedStyleRuns + [StyleRun(location: 0, length: 1, style: .heading1)]
        package.removeFileWrapper(try XCTUnwrap(package.fileWrappers?["metadata.json"]))
        let metadataWrapper = FileWrapper(regularFileWithContents: try JSONEncoder().encode(metadata))
        metadataWrapper.preferredFilename = "metadata.json"
        package.addFileWrapper(metadataWrapper)

        let document = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(document.text.string, "Safe text")
        XCTAssertEqual(document.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertNil(document.text.attribute(.boldWriterStyle, at: 1, effectiveRange: nil))
    }

    func testRevisionRestoreIgnoresMalformedStyleRanges() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Safe text", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        XCTAssertTrue(document.createRevision(named: "Safe"))
        var revision = try XCTUnwrap(document.metadata.revisions.first)
        revision.documentMetadata?.styles = malformedStyleRuns + [StyleRun(location: 0, length: 1, style: .heading1)]
        try document.restore(revision)
        XCTAssertEqual(document.text.string, "Safe text")
        XCTAssertEqual(document.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertNil(document.text.attribute(.boldWriterStyle, at: 1, effectiveRange: nil))
    }

    private var malformedStyleRuns: [StyleRun] {
        [
            StyleRun(location: -1, length: 1, style: .title),
            StyleRun(location: 0, length: -1, style: .title),
            StyleRun(location: Int.max, length: 1, style: .title),
            StyleRun(location: 1, length: Int.max, style: .title),
            StyleRun(location: 100, length: 0, style: .title),
            StyleRun(location: 8, length: 2, style: .title)
        ]
    }

    private func makeAttachedText() throws -> (NSMutableAttributedString, Data) {
        let data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHksAAAAASUVORK5CYII="))
        let imageWrapper = FileWrapper(regularFileWithContents: data)
        imageWrapper.preferredFilename = "illustration.png"
        let attachment = NSTextAttachment(fileWrapper: imageWrapper)
        let text = NSMutableAttributedString(string: "Heading\nBody ", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 7))
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: "\nAfter image", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        return (text, data)
    }

    func testSampleDemonstratesRequestedElements() throws {
        let (text, metadata) = SampleDocumentFactory.make()
        let outline = DocumentAnalysis.outline(for: text)
        XCTAssertGreaterThanOrEqual(outline.count, 4)
        XCTAssertTrue(text.string.contains("•"))
        let table = try XCTUnwrap(Tables.models(in: text).first)
        XCTAssertEqual(table.rows, 4)
        XCTAssertEqual(table.columns, 3)
        XCTAssertTrue(table.header)
        XCTAssertTrue(text.string.contains("\u{000C}"))
        XCTAssertEqual(metadata.comments.count, 1)
        XCTAssertTrue(metadata.page.showsPageNumbers)
    }

    func testEditedTextRebasesBookmarksAndCommentsAcrossContentChanges()
        throws {

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "abcdefghij"
                )
        )

        document.metadata.bookmarks = [
            DocumentBookmark(
                name:
                    "Before I",
                location:
                    8
            )
        ]

        document.metadata.comments = [
            DocumentComment(
                text:
                    "Middle",
                location:
                    3,
                length:
                    3
            )
        ]

        // Insert before both anchors.
        document.replaceEditedText(
            with:
                NSAttributedString(
                    string:
                        "XXabcdefghij"
                )
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            10
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            5
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            3
        )

        // Replace "ef" inside the existing comment with "XYZ".
        // The annotation should remain attached to "dXYZ".
        document.replaceEditedText(
            with:
                NSAttributedString(
                    string:
                        "XXabcdXYZghij"
                )
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            11
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            5
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            4
        )

        // Remove the two-character prefix again.
        document.replaceEditedText(
            with:
                NSAttributedString(
                    string:
                        "abcdXYZghij"
                )
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            9
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            3
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            4
        )

        // Delete the complete annotated span. The comment
        // remains valid as a zero-length anchor at the deletion
        // point rather than drifting into unrelated text.
        document.replaceEditedText(
            with:
                NSAttributedString(
                    string:
                        "abcghij"
                )
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            5
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            3
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            0
        )

        // A compound edit with separated mutations must not
        // collapse every anchor between the first and last edit.
        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "one two three four"
                )
        )

        document.metadata.bookmarks = [
            DocumentBookmark(
                name:
                    "Three",
                location:
                    8
            )
        ]

        document.metadata.comments = [
            DocumentComment(
                text:
                    "two",
                location:
                    4,
                length:
                    3
            )
        ]

        document.replaceEditedText(
            with:
                NSAttributedString(
                    string:
                        "ONE two three FOUR"
                )
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            8
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            3
        )
    }

}

extension PersistenceTests {
    func testDocumentSectionsRoundTripThroughMetadata() throws {
        var firstPage = PageSettings()
        firstPage.headerText = "Front Matter"

        var bodyPage = PageSettings()
        bodyPage.headerText = "Chapter Header"
        bodyPage.landscape = true

        var metadata = DocumentMetadata()
        metadata.sections = [
            DocumentSection(
                location: 0,
                page: firstPage
            ),
            DocumentSection(
                location: 42,
                page: bodyPage
            ),
        ]

        let data = try JSONEncoder().encode(metadata)
        let restored = try JSONDecoder().decode(
            DocumentMetadata.self,
            from: data
        )

        XCTAssertEqual(
            restored.sections,
            metadata.sections
        )
    }

    func testLegacyDocumentMetadataDecodesWithoutSections() throws {
        let legacy = """
        {
          "formatVersion" : 1,
          "title" : "Legacy",
          "page" : {
            "paper" : "US Letter",
            "landscape" : false,
            "topMargin" : 72,
            "bottomMargin" : 72,
            "leftMargin" : 72,
            "rightMargin" : 72,
            "showsPageNumbers" : true,
            "footerText" : "BOLD Writer"
          },
          "styleRuns" : [],
          "comments" : [],
          "bookmarks" : [],
          "notes" : "",
          "revisions" : [],
          "createdAt" : 0,
          "modifiedAt" : 0
        }
        """

        let metadata = try JSONDecoder().decode(
            DocumentMetadata.self,
            from: Data(legacy.utf8)
        )

        XCTAssertNil(metadata.sections)
    }
}

extension PersistenceTests {
    func testDocumentSectionsNormalizeOffsetsAndDuplicateBoundaries() {
        var fallback =
            PageSettings()

        fallback.headerText =
            "Fallback"

        var first =
            PageSettings()

        first.headerText =
            "First"

        var replacement =
            PageSettings()

        replacement.headerText =
            "Replacement"

        var final =
            PageSettings()

        final.headerText =
            "Final"

        let normalized =
            DocumentSection.normalized(
                [
                    DocumentSection(
                        location:
                            200,
                        page:
                            final
                    ),
                    DocumentSection(
                        location:
                            25,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            25,
                        page:
                            replacement
                    ),
                    DocumentSection(
                        location:
                            -10,
                        page:
                            first
                    ),
                ],
                textLength:
                    100,
                fallbackPage:
                    fallback
            )

        XCTAssertEqual(
            normalized.map(\.location),
            [
                0,
                25,
                100,
            ]
        )

        XCTAssertEqual(
            normalized[0].page.headerText,
            "First"
        )

        XCTAssertEqual(
            normalized[1].page.headerText,
            "Replacement"
        )

        XCTAssertEqual(
            normalized[2].page.headerText,
            "Final"
        )
    }

    func testDocumentSectionsNormalizeEmptyInputToFallback() {
        var fallback =
            PageSettings()

        fallback.footerText =
            "Fallback Footer"

        let normalized =
            DocumentSection.normalized(
                [],
                textLength:
                    50,
                fallbackPage:
                    fallback
            )

        XCTAssertEqual(
            normalized.count,
            1
        )

        XCTAssertEqual(
            normalized[0].location,
            0
        )

        XCTAssertEqual(
            normalized[0].page.footerText,
            "Fallback Footer"
        )
    }
}


extension PersistenceTests {
    func testDocumentSectionsRebaseAcrossTextEdits() {
        var first =
            PageSettings()

        first.headerText =
            "First"

        var second =
            PageSettings()

        second.headerText =
            "Second"

        var third =
            PageSettings()

        third.headerText =
            "Third"

        var metadata =
            DocumentMetadata()

        metadata.sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    5,
                page:
                    second
            ),
            DocumentSection(
                location:
                    9,
                page:
                    third
            )
        ]

        metadata.rebaseTextAnchors(
            from:
                "AAAA\\nBBBB\\nCCCC",
            to:
                "XXAAAA\\nBBBB\\nCCCC"
        )

        XCTAssertEqual(
            metadata.sections?
                .map(\.location),
            [
                0,
                7,
                11
            ]
        )

        XCTAssertEqual(
            metadata.sections?[1]
                .page
                .headerText,
            "Second"
        )

        // Inserting exactly at the second-section boundary
        // keeps the boundary before the newly inserted text.
        metadata.rebaseTextAnchors(
            from:
                "XXAAAA\\nBBBB\\nCCCC",
            to:
                "XXAAAA\\nYYBBBB\\nCCCC"
        )

        XCTAssertEqual(
            metadata.sections?
                .map(\.location),
            [
                0,
                7,
                13
            ]
        )

        // Delete across the second boundary. The boundary
        // survives at the end of the replacement/deletion.
        metadata.rebaseTextAnchors(
            from:
                "XXAAAA\\nYYBBBB\\nCCCC",
            to:
                "XXAA\\nBBBB\\nCCCC"
        )

        let sections =
            metadata.sections
            ?? []

        XCTAssertEqual(
            sections.first?
                .location,
            0
        )

        XCTAssertTrue(
            sections.allSatisfy {
                $0.location >= 0
                    && $0.location
                        <= (
                            "XXAA\\nBBBB\\nCCCC"
                                as NSString
                        )
                        .length
            }
        )

        XCTAssertEqual(
            sections.map(\.location),
            sections
                .map(\.location)
                .sorted()
        )

        XCTAssertEqual(
            sections.first?
                .page
                .headerText,
            "First"
        )
    }
}


extension PersistenceTests {
    func testRevisionContentMetadataPreservesDocumentSections()
        throws {

        var first =
            PageSettings()

        first.headerText =
            "Chapter One"

        var second =
            PageSettings()

        second.headerText =
            "Chapter Two"

        second.landscape =
            true

        let original =
            RevisionContentMetadata(
                title:
                    "Recovery Sections",
                page:
                    second,
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
                                42,
                            page:
                                second
                        )
                    ],
                styles:
                    [],
                comments:
                    [],
                bookmarks:
                    [],
                notes:
                    ""
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    original
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    RevisionContentMetadata.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.sections,
            original.sections
        )

        XCTAssertEqual(
            decoded.sections?
                .count,
            2
        )

        XCTAssertEqual(
            decoded.sections?[1]
                .location,
            42
        )

        XCTAssertTrue(
            decoded.sections?[1]
                .page
                .landscape
                ?? false
        )

        XCTAssertEqual(
            decoded.sections?[0]
                .page
                .headerText,
            "Chapter One"
        )
    }

    func testLegacyRevisionContentMetadataDecodesWithoutSections()
        throws {

        let original =
            RevisionContentMetadata(
                title:
                    "Legacy Revision",
                page:
                    PageSettings(),
                styles:
                    [],
                comments:
                    [],
                bookmarks:
                    [],
                notes:
                    ""
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    original
                )

        var object =
            try XCTUnwrap(
                JSONSerialization
                    .jsonObject(
                        with:
                            encoded
                    )
                    as? [String: Any]
            )

        object.removeValue(
            forKey:
                "sections"
        )

        let legacy =
            try JSONSerialization
                .data(
                    withJSONObject:
                        object
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    RevisionContentMetadata.self,
                    from:
                        legacy
                )

        XCTAssertNil(
            decoded.sections
        )
    }
}

extension PersistenceTests {
    func testDocumentSectionTextRangesUseCanonicalUTF16Boundaries() {
        let text =
            "Alpha🙂\nBeta\nGamma"

        let ns =
            text as NSString

        let beta =
            ns.range(
                of:
                    "Beta"
            )
            .location

        let gamma =
            ns.range(
                of:
                    "Gamma"
            )
            .location

        var first =
            PageSettings()
        first.footerText =
            "First"

        var second =
            PageSettings()
        second.footerText =
            "Second"

        var third =
            PageSettings()
        third.footerText =
            "Third"

        let mapped =
            DocumentSection.textRanges(
                [
                    DocumentSection(
                        location:
                            gamma,
                        page:
                            third
                    ),
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            beta,
                        page:
                            second
                    )
                ],
                textLength:
                    ns.length,
                fallbackPage:
                    PageSettings()
            )

        XCTAssertEqual(
            mapped.count,
            3
        )

        XCTAssertEqual(
            mapped[0].section.location,
            0
        )
        XCTAssertEqual(
            mapped[0].range,
            NSRange(
                location:
                    0,
                length:
                    beta
            )
        )
        XCTAssertEqual(
            mapped[0].section.page.footerText,
            "First"
        )

        XCTAssertEqual(
            mapped[1].section.location,
            beta
        )
        XCTAssertEqual(
            mapped[1].range,
            NSRange(
                location:
                    beta,
                length:
                    gamma - beta
            )
        )
        XCTAssertEqual(
            mapped[1].section.page.footerText,
            "Second"
        )

        XCTAssertEqual(
            mapped[2].section.location,
            gamma
        )
        XCTAssertEqual(
            mapped[2].range,
            NSRange(
                location:
                    gamma,
                length:
                    ns.length - gamma
            )
        )
        XCTAssertEqual(
            mapped[2].section.page.footerText,
            "Third"
        )

        // Confirm the UTF-16 model is actually being exercised:
        // the emoji occupies two UTF-16 code units.
        XCTAssertGreaterThan(
            beta,
            text.distance(
                from:
                    text.startIndex,
                to:
                    text.range(
                        of:
                            "Beta"
                    )!
                    .lowerBound
            )
        )
    }

    func testDocumentSectionTextRangesPreserveTerminalBoundary() {
        let length =
            ("Alpha" as NSString)
                .length

        var first =
            PageSettings()
        first.footerText =
            "Body"

        var terminal =
            PageSettings()
        terminal.footerText =
            "Terminal"

        let mapped =
            DocumentSection.textRanges(
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            first
                    ),
                    DocumentSection(
                        location:
                            length,
                        page:
                            terminal
                    )
                ],
                textLength:
                    length,
                fallbackPage:
                    PageSettings()
            )

        XCTAssertEqual(
            mapped.count,
            2
        )

        XCTAssertEqual(
            mapped[0].range,
            NSRange(
                location:
                    0,
                length:
                    length
            )
        )

        XCTAssertEqual(
            mapped[1].range,
            NSRange(
                location:
                    length,
                length:
                    0
            )
        )

        XCTAssertEqual(
            mapped[1].section.page.footerText,
            "Terminal"
        )
    }
}

extension PersistenceTests {
    func testDocumentSectionBreakTypesRoundTripAndLegacyDefault()
        throws {

        var page =
            PageSettings()

        page.headerText =
            "Section Header"

        var metadata =
            DocumentMetadata()

        metadata.sections = [
            DocumentSection(
                location:
                    0,
                page:
                    page,
                breakType:
                    .continuous
            ),
            DocumentSection(
                location:
                    12,
                page:
                    page,
                breakType:
                    .oddPage
            )
        ]

        let encoded =
            try JSONEncoder()
                .encode(
                    metadata
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    DocumentMetadata.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.sections?
                .map(
                    \.effectiveBreakType
                ),
            [
                .continuous,
                .oddPage
            ]
        )

        var object =
            try XCTUnwrap(
                JSONSerialization
                    .jsonObject(
                        with:
                            encoded
                    )
                    as? [String: Any]
            )

        var sections =
            try XCTUnwrap(
                object[
                    "sections"
                ]
                as? [[String: Any]]
            )

        for index
            in sections.indices {

            sections[index]
                .removeValue(
                    forKey:
                        "breakType"
                )
        }

        object[
            "sections"
        ] =
            sections

        let legacyData =
            try JSONSerialization
                .data(
                    withJSONObject:
                        object
                )

        let legacy =
            try JSONDecoder()
                .decode(
                    DocumentMetadata.self,
                    from:
                        legacyData
                )

        XCTAssertEqual(
            legacy.sections?
                .map(
                    \.effectiveBreakType
                ),
            [
                .nextPage,
                .nextPage
            ]
        )
    }

    func testSectionNormalizationPreservesBreakTypes() {
        var page =
            PageSettings()

        page.footerText =
            "Footer"

        let normalized =
            DocumentSection.normalized(
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            page,
                        breakType:
                            .continuous
                    ),
                    DocumentSection(
                        location:
                            10,
                        page:
                            page,
                        breakType:
                            .evenPage
                    )
                ],
                textLength:
                    20,
                fallbackPage:
                    page
            )

        XCTAssertEqual(
            normalized.map(
                \.effectiveBreakType
            ),
            [
                .continuous,
                .evenPage
            ]
        )
    }
}


extension PersistenceTests {
    func testWordPageNumberFormatHelpers() {
        var page =
            PageSettings()

        XCTAssertEqual(
            page.formattedPageNumber(
                27
            ),
            "27"
        )

        page.pageNumberFormat =
            "upperRoman"

        XCTAssertEqual(
            page.formattedPageNumber(
                14
            ),
            "XIV"
        )

        page.pageNumberFormat =
            "lowerRoman"

        XCTAssertEqual(
            page.formattedPageNumber(
                14
            ),
            "xiv"
        )

        page.pageNumberFormat =
            "upperLetter"

        XCTAssertEqual(
            page.formattedPageNumber(
                27
            ),
            "AA"
        )

        page.pageNumberFormat =
            "lowerLetter"

        XCTAssertEqual(
            page.formattedPageNumber(
                28
            ),
            "ab"
        )

        page.pageNumberFormat =
            "ordinal"

        XCTAssertEqual(
            page.formattedPageNumber(
                14
            ),
            "14"
        )

        XCTAssertEqual(
            page.pageNumberFormat,
            "ordinal"
        )
    }

    func testPageNumberRestartAndFormatPersist()
        throws {

        var page =
            PageSettings()

        page.pageNumberStart =
            7

        page.pageNumberFormat =
            "lowerRoman"

        let data =
            try JSONEncoder()
                .encode(
                    page
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        data
                )

        XCTAssertEqual(
            decoded.pageNumberStart,
            7
        )

        XCTAssertEqual(
            decoded.pageNumberFormat,
            "lowerRoman"
        )
    }
}


extension PersistenceTests {
    func testColumnSettingsPersistWithLegacyDefaults()
        throws {

        var page =
            PageSettings()

        XCTAssertNil(
            page.columnCount
        )

        XCTAssertNil(
            page.columnSpacing
        )

        XCTAssertEqual(
            page.effectiveColumnCount,
            1
        )

        XCTAssertEqual(
            page.effectiveColumnSpacing,
            36
        )

        page.columnCount =
            3

        page.columnSpacing =
            24

        let data =
            try JSONEncoder()
                .encode(
                    page
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        data
                )

        XCTAssertEqual(
            decoded.columnCount,
            3
        )

        XCTAssertEqual(
            decoded.columnSpacing,
            24
        )

        XCTAssertEqual(
            decoded.effectiveColumnCount,
            3
        )

        XCTAssertEqual(
            decoded.effectiveColumnSpacing,
            24
        )
    }
}


extension PersistenceTests {
    func testNextColumnBreakTypePersists() throws {
        let section =
            DocumentSection(
                location: 12,
                page: PageSettings(),
                breakType: .nextColumn
            )

        let data =
            try JSONEncoder().encode(section)

        let decoded =
            try JSONDecoder().decode(
                DocumentSection.self,
                from: data
            )

        XCTAssertEqual(decoded.location, 12)
        XCTAssertEqual(decoded.breakType, .nextColumn)
        XCTAssertEqual(decoded.effectiveBreakType, .nextColumn)
    }
}


extension PersistenceTests {
    func testPageSettingsHeaderFooterDistancesPersist()
        throws
    {
        var settings =
            PageSettings()

        settings.headerDistance =
            18

        settings.footerDistance =
            54

        let encoded =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.headerDistance,
            18
        )

        XCTAssertEqual(
            decoded.footerDistance,
            54
        )

        XCTAssertEqual(
            decoded.effectiveHeaderDistance,
            18
        )

        XCTAssertEqual(
            decoded.effectiveFooterDistance,
            54
        )

        var legacy =
            PageSettings()

        legacy.topMargin =
            80

        legacy.bottomMargin =
            100

        let legacyEncoded =
            try JSONEncoder()
                .encode(
                    legacy
                )

        let legacyDecoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        legacyEncoded
                )

        XCTAssertNil(
            legacyDecoded.headerDistance
        )

        XCTAssertNil(
            legacyDecoded.footerDistance
        )

        XCTAssertEqual(
            legacyDecoded.effectiveHeaderDistance,
            40
        )

        XCTAssertEqual(
            legacyDecoded.effectiveFooterDistance,
            50
        )
    }
}

extension PersistenceTests {
    func testPageSettingsPersistsWordGutterAndMirrorMargins()
        throws
    {
        var settings =
            PageSettings()

        settings.gutter =
            31.5

        settings.mirrorMargins =
            true

        let encoded =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.effectiveGutter,
            31.5,
            accuracy:
                0.001
        )

        XCTAssertTrue(
            decoded.usesMirrorMargins
        )
    }
}



extension PersistenceTests {
    func testPageSettingsPersistsWordGutterAtTop()
        throws
    {
        var settings =
            PageSettings()

        settings.gutter =
            24

        settings.gutterAtTop =
            true

        let encoded =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.effectiveGutter,
            24,
            accuracy:
                0.001
        )

        XCTAssertTrue(
            decoded.usesGutterAtTop
        )
    }
}


extension PersistenceTests {
    func testPageSettingsPersistsWordVerticalPageAlignment()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .center

        let encoded =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.effectiveVerticalPageAlignment,
            .center
        )
    }
}


extension PersistenceTests {
    func testPageSettingsPersistsWordVerticalJustificationBoth()
        throws
    {
        var settings =
            PageSettings()

        settings.verticalPageAlignment =
            .both

        let encoded =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded
                .effectiveVerticalPageAlignment,
            .both
        )
    }
}



extension PersistenceTests {
    func testPageSettingsPersistsWordNoColumnBalance()
        throws
    {
        var settings =
            PageSettings()

        XCTAssertNil(
            settings.noColumnBalance
        )

        XCTAssertFalse(
            settings.disablesColumnBalancing
        )

        settings.noColumnBalance =
            true

        let data =
            try JSONEncoder()
                .encode(
                    settings
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    PageSettings.self,
                    from:
                        data
                )

        XCTAssertEqual(
            decoded.noColumnBalance,
            true
        )

        XCTAssertTrue(
            decoded.disablesColumnBalancing
        )
    }
}
